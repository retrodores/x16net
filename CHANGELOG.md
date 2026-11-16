# Changelog

## 0.1.3 — experimental

* Write Gopher integration logs as UTF-8 on Windows, including ROM control bytes.
* Gopher PRG, library binary and ABI are unchanged from 0.1.2.

## 0.1.2 — experimental

* Add the Prog8 Gopher demo: menus, wrapped text, search, eight-location Back
  history and streamed binary downloads with overwrite protection.
* Test the shared protocol module through the full emulator on Linux/Windows,
  including fragmentation, dot-stuffing, malformed menus and size limits.
* Include x16net-gopher.prg with release packages and as a standalone asset.
* Library binary, pure bindings and ABI remain unchanged.
* Preserve credit to David Murray's ROMTERM and TexElec's serial/network card.

## 0.1.1 — experimental

* Write emulator test logs as UTF-8 on Windows; retain exact raw-byte decoding.
* Release packages are gated by native Windows and Linux integration tests.
* Library binary and ABI are unchanged.


## 0.1.0 — experimental

* Full-emulator TCP integration through compiled pure Prog8 bindings and the
  standalone binary, with normal and fragmented replies on Linux and Windows.
* Explicit acknowledgment of David Murray's ROMTERM and TexElec's Commander X16
  Serial & ESP32 Network Card, with a direct link to the card page.
* Binary ABI and payload code remain unchanged.
* Tag-driven releases provide ZIP/tar.gz packages, standalone assets and checksums
  after all model, binding and native networking checks pass.

* Standalone 65C02 binary at $8000 with twelve versioned jump-table entries.
* UART setup, byte/block serial I/O, status, bounded modem preparation,
  quiet raw TCP dialing and DTR disconnect.
* Pure Prog8 extsub bindings and assembly constants generated from one ABI list.
* Caller-buffer validation, partial counts, no zero-page/display/IRQ ownership.
* Machine-code TAP suite, randomized boundary cases, mutation checks, compiled
  examples, stock-emulator ABI smoke test and GitHub Actions.
* Real-card verification remains pending. No TLS or protocol parsers included.
