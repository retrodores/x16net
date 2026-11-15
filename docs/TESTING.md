# Tests and CI

The tests execute assembled machine code, not a rewrite of the library in Python.
py65 runs a 65C02 with a register-level UART and scripted modem test double.
The model includes DLAB, scratch register, FIFOs, CTS stalls, TX busy, line errors,
carrier transitions, DTR hangup, quiet dialing and immediately queued payload.
It is deliberately NOT the ESP32 firmware or cycle-accurate serial hardware.

make test emits TAP and a JSON report. Cases cover every jump-table entry,
all byte values, all baud divisors, return flags/registers, partial transfers,
page crossings, memory canaries, zero-page integrity, invalid pointers/endpoints,
bounded noise/timeouts, immediate payload, EOF, reconnection and fault states.
Seeded tests vary data and buffer placement. CI uses three fixed seeds under
Python 3.11/3.12/3.13. The harness limits instructions for every call.

The adverse indexed-store model simulates a destructive receive-register read
when an indexed UART store is used. This checks the conservative no-indexed-store
design; it does not claim py65 normally models real CPU bus strobes.

t/mutations.py deliberately damages the ABI magic, baud divisor, TX instruction,
receive carry, quiet dial setting and DTR hangup. The suite must reject all six
mutants, and the original binary is restored even after failures.
Do not run mutation tests concurrently against the same build directory.

Compiled Prog8 examples check binding syntax, return-register declarations and
memory reservations. t/run_x16_smoke.py loads/calls the binary on stock r49
x16emu in headless testbench mode. That covers no serial/network hardware.
Run with X16EMU and X16ROM pointing at a matching emulator/ROM pair, or fetch the
pinned official r49 package using tools/fetch-emulator.sh.

CI compares rebuilt bytes with bin/x16net.bin and verifies SHA256SUMS. Compiler
and emulator downloads are version pinned with SHA-256 checks. Artifact uploads
include TAP logs, the binary, labels and a distribution archive. The archive
does not bundle upstream compilers, emulators, firmware or X16 ROMs.

## Evidence boundaries

Model tests establish behavior against the stated model, and can catch real
machine-code errors such as flags, pointer arithmetic and incorrect ASCII bytes.
They cannot establish wiring/polarity, ESP32 firmware response timing, real baud
accuracy, FIFO trigger behavior, or Internet interoperability. See the explicit
physical-card checklist before describing networking as hardware validated.

## Full-emulator networking

network_test.p8 is compiled with the unchanged pure Prog8 bindings. It loads
x16net.bin, checks the ABI and UART/modem setup, connects to a local fixture,
verifies an immediate 256-byte binary reply, exercises byte and block calls,
checks partial counts across 4096 block bytes, then checks EOF and shutdown.
The host independently verifies all 4104 transmitted bytes, including NUL, FF,
CR/LF and +++ sequences. No payload translation or modem-text filtering occurs.

    make network-program
    X16EMU=/path/to/serial-network/x16emu X16ROM=/path/to/rom.bin make integration PYTHON=.venv/bin/python

The runner takes --fragment and --delay for deterministic reply fragmentation.
CI tests ordinary replies and delayed 17-byte fragments on Linux and native
Windows. Both jobs use the same compiled PRG/binary from the Prog8 build job.
The emulator source is pinned at 7ff49ec69c28cfc04ccdab1a5846d816f53f220e in
https://github.com/oodler577/x16-emulator/tree/serial-network . Update this pin
only after validating the new emulator revision. The existing stock-emulator
ABI test remains separate, so basic binding calls do not depend on the fork.

These tests validate the complete software path to host TCP, but still do not
validate physical-card firmware or wiring. CI fixtures use loopback only.
