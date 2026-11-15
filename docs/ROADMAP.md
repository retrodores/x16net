# Follow-up work

## Physical card validation first

Complete HARDWARE_TESTING.md before describing this as hardware validated.
Check installed Zimodem version, baud, RTS/CTS/DTR/DCD polarity, quiet dialing,
early remote close, final queued bytes, reconnects and repeated binary hashes.

## Full X16 emulator serial card

Extend a separate fork of X16Community/x16-emulator; do not put emulator-specific
network calls in x16net.bin. Emulate both UART register windows, DLAB, scratch
registers, FIFOs, baud timing, line/modem status, RTS/CTS and interrupts. Add a
host TCP bridge exposing the Zimodem command subset to the emulated ESP UART.
Keep actual Internet access opt-in and use loopback fixture servers in CI.

Distinguish firmware-compatible behavior from convenient simulation. Existing
UART/modem model tests do not substitute for a full emulator or real firmware.
Test unmodified x16net.bin in that emulator, and compare traces with hardware.

## Later library extensions

* Gopher and HTTP parsers above the raw transport.
* Packet-mode adapter if needed for stronger EOF/error framing.
* Cooperative/asynchronous connect control, optional IRQ/ring-buffer backend.
* Timed UART/firmware queue draining based on real-card measurements.
* Additional language examples and configurable load-address builds.
* TLS only after verifying installed firmware capabilities; no current claim.
