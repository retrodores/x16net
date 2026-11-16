# x16net development

Work on the Prog8 VM checkout at /opt/x16net; primary branch is master.
This repository is a standalone 65C02 binary with Prog8 bindings, not a terminal.
Do not modify XVI, VTUI, the system emulator, or unrelated repositories.

* src/x16net.asm is the implementation; 64tass builds a headerless blob at $8000.
* Grow the reusable library when an application needs a shared capability or
  transport efficiency improvement. Keep source, tests, bindings, distributed
  binary and release provenance in sync in this repository; avoid app-only
  binary patches. Display rendering remains an application concern.
* The first 12 JMP slots and the ABI header are public. Preserve compatible slots.
* tools/generate_bindings.py owns Prog8 and assembly bindings. Regenerate both
  after ABI edits and compile every example.
* The library owns no zero page, installs no interrupts, and touches no display.
* Buffers are caller-owned unbanked RAM $0200..$7fff. Code must be writable RAM.
* Calls are non-reentrant. Never invoke from an interrupt handler.
* All waits must be bounded, including continuous input/noise. No unbounded retry.
* Use explicit ASCII for commands and byte-exact payloads.
* Keep firmware/model assumptions distinct from hardware evidence.
* Run make check with PYTHON=.venv/bin/python and t/mutations.py after logic edits.
* Tests emit TAP; see t/AGENTS.md. Real hardware is unavailable for this first pass.
* t/run_network.py exercises the separate serial-network emulator fork. Keep
  emulator source changes in that repository, not in this library.
* Preserve credit to David Murray's ROMTERM and TexElec's card, including the
  linked card page, in README.md and docs/SOURCES.md.
