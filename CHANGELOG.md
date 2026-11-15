# Changelog

## Unreleased

* Full-emulator TCP integration through compiled pure Prog8 bindings and the
  standalone binary, with normal and fragmented replies on Linux and Windows.
* Explicit acknowledgment of David Murray's ROMTERM and TexElec's Commander X16
  Serial & ESP32 Network Card, with a direct link to the card page.
* Binary ABI and payload code remain unchanged.

## 0.1.0 — experimental

* Standalone 65C02 binary at $8000 with twelve versioned jump-table entries.
* UART setup, byte/block serial I/O, status, bounded modem preparation,
  quiet raw TCP dialing and DTR disconnect.
* Pure Prog8 extsub bindings and assembly constants generated from one ABI list.
* Caller-buffer validation, partial counts, no zero-page/display/IRQ ownership.
* Machine-code TAP suite, randomized boundary cases, mutation checks, compiled
  examples, stock-emulator ABI smoke test and GitHub Actions.
* Real-card verification remains pending. No TLS or protocol parsers included.
