#!/usr/bin/env python3
"""Execute the shipping machine code against a controlled UART/modem model."""
import io
import json
import os
from pathlib import Path
import random
import sys
import traceback
import unittest
from hardware import BINARY, ENTRY, EXECUTED, ROOT, SYMBOLS, Machine

class BinaryTests(unittest.TestCase):
    def test_abi_header_and_every_jump(self):
        self.assertLess(len(BINARY), 0x1f00)
        self.assertEqual(BINARY[36:44], b"X16N\1\0\x0c\0")
        self.assertEqual(int.from_bytes(BINARY[44:46], "little"), len(BINARY))
        names = ["init", "shutdown", "get_byte", "put_byte", "read_block",
                 "write_block", "status", "set_timeout", "prepare", "connect",
                 "disconnect", "abi_info"]
        for i, name in enumerate(names):
            self.assertEqual(BINARY[i*3], 0x4c)
            self.assertEqual(int.from_bytes(BINARY[i*3+1:i*3+3], "little"), SYMBOLS[name])
        self.assertEqual(Machine().call("abi_info"), (1, 0, 0x80, False))

    def test_uninitialized_operations(self):
        for name in ("get_byte", "put_byte", "status", "prepare", "connect", "disconnect"):
            self.assertEqual(Machine().call(name)[::3], (5, True), name)

    def test_all_baud_rates_and_dlab(self):
        for i, divisor in enumerate((96,48,24,16,8,4,2,1)):
            m = Machine()
            self.assertEqual(m.init(i)[0], 0)
            self.assertEqual(m.uart.divisor, [divisor, 0])
            self.assertEqual(m.uart.reg[3], 3)
            self.assertEqual(m.uart.reg[1], 0)
            self.assertEqual(m.uart.reg[2], 0x87)
            self.assertEqual(m.uart.reg[4], 0x27)
            self.assertEqual(m.uart.tx, b"")

    def test_explicit_ports(self):
        for port in range(0x9f60, 0xa000, 8):
            if port in (0x9fb0, 0x9fb8):
                continue
            m = Machine(port)
            self.assertEqual(m.init()[0], 0, hex(port))

    def test_invalid_port_and_baud_no_hardware_writes(self):
        for port in (0, 0x9f00, 0x9f5f, 0x9fe1, 0x9fb0, 0x9fb8, 0xa000):
            m = Machine()
            self.assertEqual(m.call("init", 4, port & 255, port >> 8)[0], 3)
            self.assertEqual(m.uart.writes, [])
        for baud in (8, 255):
            m = Machine()
            self.assertEqual(m.init(baud)[0], 3)
            self.assertEqual(m.uart.writes, [])

    def test_card_absent_is_detected(self):
        m = Machine(present=False)
        self.assertEqual(m.init()[::3], (4, True))
        self.assertEqual(m.call("get_byte")[0], 5)

    def test_shutdown_decimal_mode_still_addresses_correct_registers(self):
        m = Machine()
        m.init()
        self.assertEqual(m.call("shutdown",p=0x28)[0],0)
        self.assertEqual(m.uart.reg[4],4)
        self.assertEqual(m.uart.reg[1],0)

    def test_scratch_register_restored(self):
        m = Machine()
        m.uart.reg[7] = 0xf3
        m.init()
        self.assertEqual(m.uart.reg[7], 0xf3)

    def test_receive_empty_and_all_256_byte_values(self):
        m = Machine()
        m.init()
        self.assertEqual(m.call("get_byte")[::3], (1, True))
        for value in range(256):
            m.uart.rx.append(value)
            self.assertEqual(m.call("get_byte")[::3], (value, False))

    def test_send_all_256_byte_values(self):
        m = Machine()
        m.init()
        for value in range(256):
            self.assertEqual(m.call("put_byte", value)[::3], (0, False))
        self.assertEqual(m.uart.tx, bytes(range(256)))

    def test_transmit_never_reads_receive_register(self):
        m = Machine()
        m.init()
        m.indexed_store_dummy_read = True
        m.uart.rx.extend(b"receive")
        m.call("put_byte", 42)
        self.assertEqual(bytes(m.uart.rx), b"receive")
        self.assertEqual(m.uart.tx, b"*")

    def test_cts_stall_does_not_write(self):
        m = Machine()
        m.init()
        m.uart.cts = False
        self.assertEqual(m.call("put_byte", 42)[::3], (1, True))
        self.assertEqual(m.uart.tx, b"")
        m.uart.cts = True
        self.assertEqual(m.call("put_byte", 42)[0], 0)
        self.assertEqual(m.uart.tx, b"*")

    def test_busy_transmitter_does_not_write(self):
        m = Machine()
        m.init()
        m.uart.busy = 10000
        self.assertEqual(m.call("put_byte", 42)[0], 1)
        self.assertEqual(m.uart.tx, b"")

    def test_line_errors_not_reported_as_data(self):
        for flag in (2,4,8,16,30):
            m = Machine()
            m.init()
            m.uart.rx.append(99)
            m.uart.line_error = flag
            self.assertEqual(m.call("get_byte")[::3], (7, True))
            self.assertEqual(list(m.uart.rx), [99])

    def test_status_registers_and_state(self):
        m = Machine()
        m.init()
        a,x,y,c = m.call("status")
        self.assertEqual((a,x,y,c), (1,0x60,0x10,False))
        m.uart.carrier = True
        self.assertEqual(m.call("status")[2], 0x90)

    def test_timeout_24bit_and_zero_rejection(self):
        m = Machine()
        for value in (1, 256, 65536, 0x123456, 0xffffff):
            self.assertEqual(m.timeout(value)[0], 0)
            addr = SYMBOLS["timeout"]
            self.assertEqual(bytes(m.mem[addr:addr+3]), value.to_bytes(3, "little"))
        self.assertEqual(m.timeout(0)[::3], (3, True))
        self.assertEqual(bytes(m.mem[addr:addr+3]), b"\xff\xff\xff")

    def test_shutdown_and_reinitialize(self):
        m = Machine()
        self.assertEqual(m.call("shutdown")[0], 0)
        m.init()
        self.assertEqual(m.call("shutdown")[0], 0)
        self.assertEqual(m.uart.reg[4], 4)
        self.assertEqual(m.call("get_byte")[0], 5)
        self.assertEqual(m.init()[0], 0)

    def test_decimal_mode_does_not_corrupt_arithmetic(self):
        m = Machine()
        m.init()
        m.uart.pending.extend(bytes(range(256)))
        self.assertEqual(m.call("read", 0, 0xff, 0x20, p=0x28), (0,0,1,False))
        self.assertEqual(bytes(m.mem[0x20ff:0x21ff]), bytes(range(256)))

    def test_read_blocks_across_pages(self):
        for length in (1,15,16,17,63,127,128,255,256):
            m = Machine()
            m.init()
            data = bytes((i*31)&255 for i in range(length))
            m.uart.pending.extend(data)
            a,x,y,c = m.call("read", length&255, 0xfd, 0x20)
            self.assertEqual((a,x+y*256,c), (0,length,False))
            self.assertEqual(bytes(m.mem[0x20fd:0x20fd+length]), data)

    def test_write_blocks_across_pages(self):
        for length in (1,16,17,127,255,256):
            m = Machine()
            m.init()
            data = bytes((i*17)&255 for i in range(length))
            m.mem[0x20fd:0x20fd+length] = data
            a,x,y,c = m.call("write", length&255, 0xfd, 0x20)
            self.assertEqual((a,x+y*256,c), (0,length,False))
            self.assertEqual(m.uart.tx, data)

    def test_partial_read_has_exact_count(self):
        m = Machine()
        m.init()
        m.uart.rx.extend(b"abc")
        self.assertEqual(m.call("read", 10, 0, 0x20), (1,3,0,True))
        self.assertEqual(bytes(m.mem[0x2000:0x2003]), b"abc")

    def test_partial_write_resume_without_duplicate_bytes(self):
        m = Machine()
        m.init()
        m.mem[0x2000:0x2004] = b"test"
        m.uart.tx_delay = 10000
        self.assertEqual(m.call("write", 4, 0, 0x20), (1,1,0,True))
        m.uart.tx_delay = m.uart.busy = 0
        self.assertEqual(m.call("write", 3, 1, 0x20), (0,3,0,False))
        self.assertEqual(m.uart.tx, b"test")

    def test_buffer_bounds_and_canaries(self):
        for operation in ("read", "write"):
            for start,length in ((0,1),(0x1ff,1),(0x8000,1),(0x9fe0,1),
                                 (0xffff,1),(0x7fff,2),(0x7f01,256)):
                m = Machine()
                m.init()
                self.assertEqual(m.call(operation,length&255,start&255,start>>8),
                                 (3,0,0,True), (operation,start,length))
            for start,length in ((0x200,1),(0x7fff,1),(0x7f00,256)):
                m = Machine()
                m.init()
                m.uart.pending.extend(b"x"*length)
                self.assertEqual(m.call(operation,length&255,start&255,start>>8)[0],0)

    def test_block_uninitialized_preserves_buffer(self):
        for operation in ("read", "write"):
            m = Machine()
            m.mem[0x2000:0x2010] = [0xa5]*16
            self.assertEqual(m.call(operation,16,0,0x20),(5,0,0,True))
            self.assertEqual(m.mem[0x2000:0x2010],[0xa5]*16)

    def test_prepare_exact_command_profile(self):
        m = Machine()
        m.ready()
        cmd = m.uart.commands[0]
        for token in (b"E0",b"Q0",b"F0",b"R0",b"&P0",b"S62=0",b"S63=2",b"S46=0"):
            self.assertIn(token,cmd)
        self.assertEqual(m.call("status")[0],2)

    def test_prepare_accepts_echo_and_blank_lines(self):
        m = Machine()
        m.init()
        m.uart.model_modem = True
        m.uart.prepare_response = b"\r\nATE0\r\nIGNORE\r\nOK\r"
        m.timeout(2048)
        self.assertEqual(m.call("prepare")[0],0)

    def test_prepare_rejects_error_and_enters_fault(self):
        m = Machine()
        m.init()
        m.uart.model_modem = True
        m.uart.prepare_response = b"ERROR\r"
        m.timeout(2048)
        self.assertEqual(m.call("prepare")[::3],(8,True))
        self.assertEqual(m.call("status")[0],4)
        self.assertEqual(m.call("connect")[0],5)

    def test_prepare_does_not_accept_substring_ok(self):
        for response in (b"NOTOK\r",b"OKAY\r",b"OK \r",b"ok\r"):
            m = Machine()
            m.init()
            m.uart.model_modem = True
            m.uart.prepare_response = response
            m.timeout(160)
            self.assertEqual(m.call("prepare")[0],2)

    def test_prepare_overlong_response_is_bounded(self):
        m = Machine()
        m.init()
        m.uart.model_modem = True
        m.uart.prepare_response = b"x"*64+b"\rOK\r"
        m.timeout(2048)
        self.assertEqual(m.call("prepare")[0],9)

    def test_prepare_no_response_and_cts_stall_timeout(self):
        for cts in (False,True):
            m = Machine()
            m.init()
            m.uart.cts = cts
            m.timeout(150)
            before = m.instructions
            self.assertEqual(m.call("prepare")[::3],(2,True))
            self.assertLess(m.instructions-before,10000)

    def test_prepare_noise_cannot_extend_total_budget(self):
        m = Machine()
        m.init()
        m.uart.model_modem = True
        m.uart.prepare_response = b"noise\r"*300
        m.timeout(180)
        self.assertEqual(m.call("prepare")[0],2)

    def test_connect_uses_quiet_raw_dial(self):
        m = Machine()
        m.ready()
        self.assertEqual(m.connect()[0],0)
        self.assertEqual(m.uart.commands[-1],b'ATQ1D"example.com:80"')
        self.assertTrue(m.uart.quiet)
        self.assertEqual(m.call("status")[0],3)

    def test_connect_preserves_immediate_payload_including_newline(self):
        m = Machine()
        payload = b"\n\0OK\rNO CARRIER\r\xff"
        m.connected(payload)
        result = bytearray()
        while len(result) < len(payload):
            a,_,_,c = m.call("get_byte")
            if not c:
                result.append(a)
        self.assertEqual(result,payload)

    def test_endpoint_validation_and_injection(self):
        for endpoint in (b"", b"a", b":80", b"a:", b"a:1:2", b'a:80"\rATZ',
                         b"a:80\n", b"a:80/evil", b"\xff:80",b"a"*96+b":80"):
            m = Machine()
            m.ready()
            tx = bytes(m.uart.tx)
            self.assertEqual(m.connect(endpoint)[0],3,endpoint)
            self.assertEqual(m.uart.tx,tx)

    def test_endpoint_page_crossing_and_upper_bound(self):
        m = Machine()
        m.ready()
        data=b"a.test:70\0"
        m.mem[0x20fc:0x20fc+len(data)]=data
        self.assertEqual(m.call("connect",x=0xfc,y=0x20)[0],0)
        m = Machine()
        m.ready()
        m.mem[0x7fff] = ord("a")
        self.assertEqual(m.call("connect",x=0xff,y=0x7f)[0],3)

    def test_endpoint_maximum_95_bytes(self):
        m = Machine()
        m.ready()
        endpoint=b"a"*92+b":70"
        self.assertEqual(len(endpoint),95)
        self.assertEqual(m.connect(endpoint)[0],0)
        self.assertEqual(m.uart.commands[-1],b'ATQ1D"'+endpoint+b'"')

    def test_failed_dial_timeout_leaves_uncertain_state(self):
        m = Machine()
        m.ready()
        m.uart.dial_success=False
        m.timeout(200)
        self.assertEqual(m.connect()[::3],(2,True))
        self.assertEqual(m.call("status")[0],4)
        for name in ("prepare","connect","get_byte","put_byte","disconnect"):
            self.assertEqual(m.call(name)[0],5,name)

    def test_carrier_delay_and_send_failure_are_bounded(self):
        m = Machine()
        m.ready()
        m.uart.dial_delay=400
        self.assertEqual(m.connect()[0],0)
        m = Machine()
        m.ready()
        m.uart.cts=False
        m.timeout(20)
        self.assertEqual(m.connect()[0],2)

    def test_eof_after_fifo_drained(self):
        m = Machine()
        m.connected()
        m.uart.rx.extend(b"end")
        m.uart.carrier=False
        for value in b"end":
            self.assertEqual(m.call("get_byte")[::3],(value,False))
        self.assertEqual(m.call("get_byte")[::3],(6,True))
        self.assertEqual(m.call("put_byte",42)[::3],(6,True))

    def test_disconnect_dtr_discards_unread_and_allows_reconnect(self):
        m = Machine()
        m.connected(b"unread data")
        self.assertEqual(m.call("disconnect")[0],0)
        self.assertFalse(m.uart.carrier)
        self.assertEqual(m.uart.reg[4],0x27)
        self.assertEqual(m.call("status")[0],2)
        self.assertFalse(m.uart.rx)
        self.assertIn((4,0x26),m.uart.writes)
        self.assertEqual(m.connect()[0],0)

    def test_disconnect_stuck_carrier_fault_keeps_dtr_low(self):
        m = Machine()
        m.connected()
        m.uart.hangup_stuck=True
        m.timeout(40)
        self.assertEqual(m.call("disconnect")[0],2)
        self.assertEqual(m.uart.reg[4],0x26)
        self.assertEqual(m.call("status")[0],4)

    def test_shutdown_drops_connection(self):
        m = Machine()
        m.connected()
        self.assertEqual(m.call("shutdown")[0],0)
        self.assertFalse(m.uart.carrier)
        self.assertEqual(m.call("status")[0],5)

    def test_seeded_random_binary_roundtrips_and_memory_ownership(self):
        rng=random.Random(int(os.environ.get("X16NET_SEED","1616")))
        for iteration in range(60):
            m=Machine()
            m.init()
            length=rng.randint(1,256)
            start=rng.randint(0x200,0x7fff-length+1)
            data=bytes(rng.randrange(256) for _ in range(length))
            m.mem[0:256]=bytes(rng.randrange(256) for _ in range(256))
            zp=m.mem[0:256]
            m.mem[start-1]=0xa6
            m.mem[start+length]=0x6a
            m.mem.trace_writes.clear()
            m.uart.pending.extend(data)
            self.assertEqual(m.call("read",length&255,start&255,start>>8)[0],0)
            self.assertEqual(bytes(m.mem[start:start+length]),data)
            self.assertEqual(m.mem[start-1],0xa6)
            self.assertEqual(m.mem[start+length],0x6a)
            self.assertEqual(m.mem[0:256],zp)
            self.assertEqual(m.call("write",length&255,start&255,start>>8)[0],0)
            self.assertEqual(m.uart.tx,data)
            for address in m.mem.trace_writes:
                self.assertTrue(0x100<=address<0x200 or start<=address<start+length
                                or 0x8000<=address<0x8000+len(BINARY),hex(address))

    def test_long_transfer_flow_control_and_binary_content(self):
        m=Machine()
        m.connected()
        data=bytes(range(256))*16
        m.uart.pending.extend(data)
        received=bytearray()
        for _ in range(16):
            self.assertEqual(m.call("read",0,0,0x20),(0,0,1,False))
            received.extend(m.mem[0x2000:0x2100])
        self.assertEqual(received,data)
        self.assertFalse(m.uart.pending)
        self.assertLessEqual(len(m.uart.rx),16)

    def test_all_operations_leave_zero_page_intact(self):
        m=Machine()
        m.mem[:256]=bytes(range(256))
        zp=m.mem[:256]
        m.ready()
        m.connect()
        m.call("status")
        m.call("get_byte")
        m.call("put_byte",42)
        m.call("read",1,0,0x20)
        m.call("write",1,0,0x20)
        m.call("disconnect")
        m.call("abi_info")
        m.call("shutdown")
        self.assertEqual(m.mem[:256],zp)

class TAPResult(unittest.TestResult):
    def startTest(self,test):
        super().startTest(test)
    def addSuccess(self,test):
        super().addSuccess(test)
        print(f"ok {self.testsRun} - {test._testMethodName}")
    def addFailure(self,test,err):
        super().addFailure(test,err)
        self.fail(test,err)
    def addError(self,test,err):
        super().addError(test,err)
        self.fail(test,err)
    def fail(self,test,err):
        print(f"not ok {self.testsRun} - {test._testMethodName}")
        for line in traceback.format_exception(*err):
            for part in line.splitlines():
                print("# "+part)

if __name__ == "__main__":
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(BinaryTests)
    result=TAPResult()
    suite.run(result)
    print(f"1..{result.testsRun}")
    report={"tests":result.testsRun,"executed_instruction_addresses":len(EXECUTED),
            "seed":os.environ.get("X16NET_SEED","1616")}
    (ROOT/"build/test-report.json").write_text(json.dumps(report,indent=2)+"\n")
    print(f"# {len(EXECUTED)} distinct machine-code instruction addresses executed")
    sys.exit(not result.wasSuccessful())
