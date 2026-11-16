# X16NET Gopher demo

A small Prog8 Gopher browser using the **pure x16net bindings** and the standalone
`x16net.bin`. It runs through the emulator's `-serialcard` bridge and is intended
for the TexElec network card at $9FE0/115200 as well. Physical-card testing is pending.

Copy `x16net-gopher.prg` and the matching `x16net.bin` into the emulator folder:

```sh
./x16emu.exe -rom rom.bin -serialcard -scale 2 -fsroot . -prg x16net-gopher.prg -run
```

On Linux use `./x16emu` in that command. The serial-network release also provides
`start-gopher.bat` and `start-gopher.sh`. Use your own compatible `rom.bin`.

The opening screen asks for **host:port**, with `gopher.floodgap.com:70` as the
editable default, followed by a selector. Press Enter for the default host and
again for the root menu. You can instead enter any reachable Gopher host/port.
This demo uses ordinary Gopher over raw TCP; it does not use AT&G or require TLS.
On physical hardware, configure the ESP32's Wi-Fi beforehand and leave the modem
in ASCII command mode. The emulator's Wi-Fi menu is a labeled host-bridge mock.

| Key | Action |
| --- | --- |
| Up/Down or k/j | Move the selection / scroll text |
| Enter | Open menu/text; prompt for search or a binary download filename |
| N or Space / P | Next / previous page |
| B or Left | Back, with up to eight prior locations |
| G | Enter a different host:port and selector |
| R | Reload |
| Q | Quit |
| Esc | Cancel a prompt or a transfer |

Menus display the Gopher item type: **1** menu, **0** text, **7** search, and
**9/5/6/g/I** binary downloads. Informational/error items remain readable but
cannot be opened; unsupported services are labeled by their original type.
Only printable ASCII is rendered, so server control bytes cannot control the
screen. Text wraps at 72 columns. Menu labels are limited to 72 visible characters.

This is a bounded demo: previews hold **8 KiB / 256 displayed lines**, selectors
hold 255 bytes and host:port holds 127 bytes. A visible notice marks a truncated
preview or missing final dot. Binary files stream to disk in 512-byte blocks,
up to **1 MiB**, without text conversion or dot processing. The destination must
be a new filename (letters, digits, dot, underscore, hyphen; up to 31 characters).
Existing files are not overwritten. Failed/cancelled downloads may leave a partial
file. Network operations have 30-second idle and five-minute transfer limits.

The application reserves memory below $8000; the library loads at $8000.
`examples/gopher_client.p8` contains protocol handling, and `examples/gopher.p8`
contains the interface. No transport implementation is copied into Prog8.

```sh
prog8c -target cx16 -out build -srcdirs prog8 examples/gopher.p8
# build/gopher.prg is distributed as x16net-gopher.prg
```

`t/gopher_test.p8` uses the same protocol module. `t/run_gopher.py` supplies a local
server, fragments responses, verifies selectors/search, compares downloaded bytes,
and tests overwrite refusal, truncation, missing terminators and malformed menus.
The tests run through the full emulator on Linux and Windows.

Protocol reference: [RFC 1436](https://www.rfc-editor.org/rfc/rfc1436).
Serial reference credit: David Murray's ROMTERM and
[TexElec's Commander X16 Serial & ESP32 Network Card](https://texelec.com/product/commander-x16-serial-network-card/).
