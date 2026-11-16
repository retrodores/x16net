Experimental Commander X16 networking library, now with a Prog8 Gopher demo.

Download x16net-gopher.prg and x16net.bin together, or use the complete package.
The Gopher demo supports menus, text, search, Back and binary downloads. See
docs/GOPHER.md for commands, limits and physical-card setup. The standalone
library binary and pure Prog8 bindings are unchanged from 0.1.1.

Download the ZIP or tar.gz for the binary, pure Prog8 bindings, assembly
interface, examples, documentation and MIT license. Individual binary/binding
files are also attached. Verify downloads with SHA256SUMS.

Load the headerless `x16net.bin` into writable RAM at **$8000** and reserve that
memory in the caller. The Prog8 examples use `%memtop $8000`. The default network
UART is **$9FE0**, with baud index 4 selecting **115200**.

Features include byte/block serial I/O, RTS/CTS, bounded modem setup and dialing,
raw TCP streaming, carrier status and DTR disconnect. The twelve-entry jump table
is documented in `docs/ABI.md`.

The full software path has model tests, mutation checks, a stock-emulator ABI
test, and compiled Prog8 TCP integration on Linux and Windows. Physical-card
verification is still pending. The demo includes a Gopher parser; HTTP parsing and TLS are not library APIs.

For emulator networking, use the
[serial-network emulator preview](https://github.com/oodler577/x16-emulator/releases)
and its [network setup wiki](https://github.com/oodler577/x16-emulator/wiki).

Credit to **David Murray's ROMTERM** and **TexElec's**
[Commander X16 Serial & ESP32 Network Card](https://texelec.com/product/commander-x16-serial-network-card/)
and published programming documentation. The implementation is independent and
does not bundle ROMTERM or ESP32 firmware.
