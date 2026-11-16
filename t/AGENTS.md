# Maintaining the test suite

Tests execute the actual build/x16net.bin with py65's 65C02 CPU.
hardware.py models only the documented UART/Zimodem subset; it is not the ESP32
firmware and must not be described as hardware validation.

For changes, add behavioral cases to test_binary.py rather than comparing source
text or mirroring assembly implementation. Cover carry and returned registers,
partial counts, bounded waits, zero-page integrity and memory canaries.
Keep RNG deterministic; CI varies X16NET_SEED. Every test must have an instruction
limit. Do not mask failures with skips when an expected dependency is installed.

Run:
    make check PYTHON=.venv/bin/python
    .venv/bin/python t/mutations.py

run_x16_smoke.py needs X16EMU/X16ROM. It exercises Prog8 loading and external
calls on a stock emulator, and deliberately does not claim serial support.

network_test.p8 uses only pure bindings to the standalone binary. run_network.py
starts a loopback fixture, injects only the port into the compiled PRG, and checks
both guest TAP and host bytes. X16EMU must point to the serial-network emulator.
CI compiles once and runs the same PRG on Linux and Windows. All stream waits
and fixture operations are bounded; normal and fragmented replies must pass.

Gopher demo: examples/gopher_client.p8 is shared between the UI and
t/gopher_test.p8. Compile the latter with source paths prog8 and examples.
t/run_gopher.py runs that PRG through the full emulator, verifies its TAP and
the host-side selectors and downloaded bytes. Test only local fixtures.

The X16-only Gopher renderer is shared with gopher_view_test.p8. Build with
make gopher-display-program and run t/run_gopher_view.py with X16EMU/X16ROM.
The checks read real emulated VERA cells and attributes, including the last
column and overlap-safe scrolling; they must not be replaced by source matching.
