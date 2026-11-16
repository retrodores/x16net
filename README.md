# x16net

A small standalone networking library for the Commander X16 Serial & ESP32 Network
Card, with Prog8 bindings and a documented machine-code interface for other languages.

**Status: experimental 0.1.0. Includes model, ABI, and full-emulator TCP tests;
physical-card verification remains pending.**

The implementation is independent 65C02 assembly built with 64tass. The binary
provides a callable UART/network interface for programs written in any language.
Credit goes to **David Murray's ROMTERM**, whose UART behavior provided a valuable
reference, and to **TexElec** for the
[Commander X16 Serial & ESP32 Network Card](https://texelec.com/product/commander-x16-serial-network-card/)
and its hardware/programming documentation. ROMTERM is linked from that card page.
See [source acknowledgments](docs/SOURCES.md) for the full references.

## What is included

* Headerless `x16net.bin`, loaded into writable unbanked RAM at `$8000`.
* Twelve stable JMP entry points; ABI version/header and no zero-page allocation.
* Explicit UART selection, eight baud rates, 8N1, hardware FIFO and RTS/CTS.
* Nonblocking byte and caller-buffer reads/writes with partial-transfer counts.
* Zimodem preparation, one raw TCP stream, carrier status and DTR disconnect.
* Bounded command/connect/disconnect waits, binary byte preservation, and errors.
* Generated Prog8 and assembly bindings; HTTP request and ABI smoke examples.
* TAP tests executing the shipping machine code, seeded boundary tests, mutation
  checks, reproducible binary checks, compiled Prog8 ABI smoke testing, and
  full-emulator TCP integration on Linux and Windows.

No HTTP parser, Gopher menu parser, TLS/HTTPS, UDP, concurrent sockets, IRQ driver,
Wi-Fi provisioning, or full serial-card emulator is bundled in this library.
TCP/IP and DNS are supplied by the ESP32's installed Zimodem firmware.

## Build and test

On Debian/Ubuntu install 64tass, Python 3 with venv, Make, and Java 21. Install
Prog8 14.0-BETA3 as `prog8c`, or use the pinned download helper:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements-test.txt
sh tools/fetch-prog8.sh
make check PYTHON=.venv/bin/python PROG8C="$PWD/.tools/prog8c"
.venv/bin/python t/mutations.py
make package PYTHON=.venv/bin/python PROG8C="$PWD/.tools/prog8c"
```

The binary itself needs only `make build/x16net.bin`; Java/Prog8 are needed for
the examples, and Python/py65 for tests. CI does not contact public test servers.

## Using it

Download a tested package from [Releases](https://github.com/retrodores/x16net/releases).
The checked-in binary is also in [bin/](bin/); CI rebuilds it and verifies byte equality.
Copy it to the X16 disk as `x16net.bin`. Load the headerless file at `$8000`
(use Prog8 `diskio.load_raw`, or the equivalent loader in your language).
Reserve `$8000..$9eff` in the caller; Prog8 examples use `%memtop $8000`.
Import [prog8/x16net.p8](prog8/x16net.p8) through the compiler source path.

1. Configure Wi-Fi beforehand using ROMTERM and `AT+CONFIG`.
2. Leave the modem in its normal ASCII AT command mode, at a known baud rate.
3. Initialize UART `$9fe0`, baud index 4 (115200), then call `prepare`.
4. Connect using a NUL-terminated ASCII endpoint such as `example.com:80`.
5. Read/write raw bytes; retry `ERR_AGAIN` in your event loop, preserving partial
   counts. Your application controls its transfer/idle deadline.
6. Disconnect explicitly when finished; this discards unread received data.

The library takes exclusive ownership of the selected UART and modem session.
`prepare` closes existing modem connections/listeners, changes volatile command
settings, and does not save them to flash. Baud changes must also match the ESP32;
initializing the UART does not change the modem's baud.

See [the ABI](docs/ABI.md), [Prog8 usage](docs/PROG8.md),
[testing](docs/TESTING.md), and [hardware validation](docs/HARDWARE_TESTING.md).

## Why quiet mode?

A terminal can display `NO CARRIER`; a binary download must not receive those bytes
as file contents. After a confirmed preparation exchange, dialing uses `ATQ1D`
and watches DCD rather than parsing a CONNECT line. Failed/unsupported dials return
TIMEOUT, not a fabricated detailed network error. The library does not search
payloads for modem strings: payload bytes `OK`, `NO CARRIER`, NUL and $ff are data.

Carrier detection and ESP32 queued-output timing still require real-card
validation. EOF currently means DCD is inactive and the UART FIFO is empty; it
cannot prove that an ESP32 firmware queue has drained. Protocol-level lengths and
checksums should be verified during hardware tests before relying on downloads.

## Follow-up

[ROADMAP.md](docs/ROADMAP.md) records full X16 serial-card emulation with a host TCP
bridge, protocol helpers, and work gated on physical-card results.

MIT licensed. This project is not an official TexElec or Commander X16 release.

## Publishing

VERSION sets the package version. Push a matching v* tag to build and test all
platforms, then publish the package, individual binary/bindings and checksums.
The publisher records its CI results and publication provenance in refs/notes/releases.
