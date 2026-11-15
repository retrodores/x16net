"""65C02 execution harness plus bounded, register-level UART/modem model.

This is a test double, NOT hardware validation or a Zimodem emulator. It models
the documented subset and deliberately exposes timing/flow/error controls.
"""
from collections import deque
from pathlib import Path
import re
from py65.devices.mpu65c02 import MPU

ROOT = Path(__file__).resolve().parents[1]
SYMBOLS = {}
for line in (ROOT / "build/x16net.labels").read_text().splitlines():
    m = re.match(r"(\w+)\s*=\s*\$([0-9a-fA-F]+)", line)
    if m:
        SYMBOLS[m[1]] = int(m[2], 16)
BINARY = (ROOT / "build/x16net.bin").read_bytes()
ENTRY = {name: 0x8000 + i*3 for i, name in enumerate([
    "init", "shutdown", "get_byte", "put_byte", "read", "write", "status",
    "set_timeout", "prepare", "connect", "disconnect", "abi_info"
])}
EXECUTED = set()

class UART:
    def __init__(self, base=0x9fe0, present=True):
        self.base = base
        self.present = present
        self.reg = [0] * 8
        self.divisor = [0, 0]
        self.rx = deque()
        self.pending = deque()
        self.tx = bytearray()
        self.writes = []
        self.commands = []
        self.command = bytearray()
        self.carrier = False
        self.cts = True
        self.busy = 0
        self.tx_delay = 0
        self.line_error = 0
        self.model_modem = False
        self.quiet = False
        self.dial_success = True
        self.dial_delay = 1
        self.dial_countdown = None
        self.hangup_stuck = False
        self.initial_payload = b""
        self.prepare_response = b"\rOK\r"
        self.fifo_overruns = 0
        self.drop_after = None

    def step(self):
        if self.dial_countdown is not None:
            self.dial_countdown -= 1
            if self.dial_countdown <= 0:
                self.dial_countdown = None
                if self.dial_success:
                    self.carrier = True
                    self.pending.extend(self.initial_payload)
        # Model a hardware FIFO, auto RTS throttling the ESP's queued bytes.
        if self.pending and len(self.rx) < 16:
            self.rx.append(self.pending.popleft())
        if self.busy:
            self.busy -= 1

    def read(self, off):
        if not self.present:
            return 0x9f
        if off in (0, 1) and self.reg[3] & 0x80:
            return self.divisor[off]
        if off == 0:
            return self.rx.popleft() if self.rx else 0
        if off == 5:
            return (1 if self.rx else 0) | self.line_error | (0x60 if self.cts and not self.busy else 0)
        if off == 6:
            return (0x80 if self.carrier else 0) | (0x10 if self.cts else 0)
        return self.reg[off]

    def write(self, off, value):
        self.writes.append((off, value))
        if not self.present:
            return
        if off in (0, 1) and self.reg[3] & 0x80:
            self.divisor[off] = value
            return
        if off == 0:
            if not self.cts or self.busy:
                raise AssertionError("write to UART before TX ready")
            self.tx.append(value)
            self.busy = self.tx_delay
            if self.model_modem and not self.carrier:
                if value == 13:
                    cmd = bytes(self.command)
                    self.commands.append(cmd)
                    self.command.clear()
                    if cmd.startswith(b"ATE0"):
                        self.quiet = False
                        self.pending.extend(self.prepare_response)
                    elif cmd.startswith(b'ATQ1D"') and cmd.endswith(b'"'):
                        self.quiet = True
                        self.dial_countdown = self.dial_delay
                    else:
                        raise AssertionError(f"unexpected modem command {cmd!r}")
                else:
                    self.command.append(value)
        elif off == 2:
            if value & 2:
                self.rx.clear()
            self.reg[off] = value
        elif off == 4:
            old = self.reg[off]
            self.reg[off] = value
            if old & 1 and not value & 1 and not self.hangup_stuck:
                self.carrier = False
                self.pending.clear()
        else:
            self.reg[off] = value

class Memory:
    def __init__(self, uart):
        self.ram = [0] * 65536
        self.uart = uart
        self.trace_writes = []
        self.trace_io = []
        self.track = False

    def __getitem__(self, address):
        if isinstance(address, slice):
            return self.ram[address]
        address &= 0xffff
        if 0x9f00 <= address < 0xa000:
            self.trace_io.append(("r", address))
            if self.uart.base <= address < self.uart.base + 8:
                return self.uart.read(address-self.uart.base)
            raise AssertionError(f"unexpected I/O read {address:04x}")
        return self.ram[address]

    def __setitem__(self, address, value):
        if isinstance(address, slice):
            self.ram[address] = value
            return
        address &= 0xffff
        if 0x9f00 <= address < 0xa000:
            self.trace_io.append(("w", address))
            if self.uart.base <= address < self.uart.base+8:
                self.uart.write(address-self.uart.base, value)
                return
            raise AssertionError(f"unexpected I/O write {address:04x}")
        if self.track:
            self.trace_writes.append(address)
        self.ram[address] = value & 255

class Machine:
    def __init__(self, base=0x9fe0, present=True):
        self.uart = UART(base, present)
        self.mem = Memory(self.uart)
        self.mem[0x8000:0x8000+len(BINARY)] = BINARY
        self.cpu = MPU(memory=self.mem)
        self.instructions = 0
        self.indexed_store_dummy_read = False

    def call(self, name, a=0, x=0, y=0, p=0x20, limit=500000):
        c = self.cpu
        c.a, c.x, c.y, c.p, c.sp = a, x, y, p, 0xff
        c.pc = ENTRY[name]
        # RTS sentinel at $0700.
        c.stPushWord(0x06ff)
        self.mem.track = True
        for _ in range(limit):
            if c.pc == 0x0700:
                assert c.sp == 0xff, "unbalanced hardware stack"
                return c.a, c.x, c.y, bool(c.p & 1)
            EXECUTED.add(c.pc)
            self.uart.step()
            # Conservative adverse bus model: py65 itself omits dummy reads.
            # Ensure hardware TX stores remain safe even with indexed read strobes.
            if self.indexed_store_dummy_read and self.mem[c.pc] == 0x9d:
                target = (self.mem[c.pc+1] | self.mem[c.pc+2] << 8) + c.x
                if 0x9f00 <= target < 0xa000:
                    self.mem[target]
            c.step()
            self.instructions += 1
        raise AssertionError(f"{name} exceeded instruction budget at {c.pc:04x}")

    def init(self, baud=4):
        return self.call("init", baud, self.uart.base & 255, self.uart.base >> 8)

    def timeout(self, polls):
        return self.call("set_timeout", (polls >> 16) & 255, polls & 255, (polls >> 8) & 255)

    def ready(self):
        assert self.init()[0] == 0
        self.uart.model_modem = True
        self.timeout(2048)
        assert self.call("prepare")[0] == 0

    def connect(self, endpoint=b"example.com:80"):
        self.mem[0x2000:0x2000+len(endpoint)+1] = endpoint + b"\0"
        return self.call("connect", x=0, y=0x20)

    def connected(self, payload=b""):
        self.ready()
        self.uart.initial_payload = payload
        assert self.connect()[0] == 0
