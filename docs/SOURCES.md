# Reference material and provenance

x16net is independently implemented from published UART documentation and
observed reference-program behavior. ROMTERM code and the friend's uploaded
source are not redistributed. Neither is included under this project's MIT
license. Prog8 is a separate GPL-licensed compiler; its runtime libraries remain
under their upstream terms. No upstream serial.p8 implementation is copied here.

Reviewed sources:

* TexElec card description and programmer notes:
  https://texelec.com/product/commander-x16-serial-network-card/
* TI TL16C2550 data sheet SLWS161E:
  https://www.ti.com/lit/ds/symlink/tl16c2550.pdf
* Zimodem source reviewed at a534e5129d88b8b09aa01fe17498d5cd5368569e:
  https://github.com/bozimmerman/Zimodem/tree/a534e5129d88b8b09aa01fe17498d5cd5368569e
  Especially zimodem.ino card pin assignments, zstream.ino DTR and quiet
  stream-exit behavior, zcommand.ino command parsing and suppressResponses.
* Prog8 serial module, blob 170a5c736edaabaeb274057aebbb838cd876929a:
  https://github.com/irmen/prog8/blob/master/compiler/res/prog8lib/cx16/serial.p8
* Prog8 serialdownload example, blob d74b44e6c6fe03b50daea22060764a38a9c5355e:
  https://github.com/irmen/prog8/blob/master/examples/cx16/serialdownload.p8

The upstream Prog8 module confirms divisor values, MCR=$27 and FCR=$87 (eight-byte
RX trigger), and discusses dummy-read hazards with indexed stores. x16net uses
plain absolute UART stores, including TX, as a conservative solution.
It retains bounded operations instead of the reference's unbounded wait loops.

serialdownload uses the modem's AT&G file-fetch feature. serial.p8 contains a
warning about that feature's binary mode and offers a hex-mode alternative.
x16net uses raw ATD TCP streams instead; that does not establish that raw
streams are free of firmware issues. It needs independent byte/hash validation.

The user also supplied serial_simple.zip (libuart.p8 and main.p8), reported by its
author to have communicated with real hardware. It confirms $9fe0/$9fe8 mapping
and 115200 operation. It is a terminal experiment: its detection always returns
true and some writes omit readiness checks. Its MCR=$2b differs from the
ROMTERM/upstream $27; comments alone do not resolve the physical option-pin
behavior. x16net follows ROMTERM/upstream and flags pin verification for hardware
testing. No author's identity or redistribution license was supplied.

ROMTERM.PRG supplied by the user identifies v1.23, copyright 2024 David Murray.
SHA-256: f9e91d84ac5eed5b2d5f137458cf446a0913e2714fcba4f25f40c095f515787f.
Its UART initialization, polling, register tables and terminal coupling were
inspected. Private offsets are not an ABI and are not used by x16net.
