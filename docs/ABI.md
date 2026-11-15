# Binary interface: ABI 1.0

Load the raw, headerless binary at $8000 in writable unbanked RAM. All pointers
and words are little-endian: XY means X=low, Y=high. Call entries with JSR, not
a jump into private implementation labels. The binary uses self-modifying
absolute operands and cannot execute from ROM.

Every call may clobber A, X, Y and processor arithmetic flags. Return registers
are listed below. Success clears carry; failure sets carry with A=error code.
Exception: get_byte returns the received byte in A on success; status and
abi_info return information rather than error code zero. Decimal mode is cleared
by arithmetic/transport entries and must not be relied upon after any call.
The interrupt-disable flag is not changed. No zero-page or KERNAL virtual
registers are allocated. The hardware stack must have at least 32 bytes free.

## Jump table

| Offset | Address | Entry | Input | Successful output |
|---|---|---|---|---|
| +0 | $8000 | init | A=baud index, XY=UART base | A=0 |
| +3 | $8003 | shutdown | none | A=0 |
| +6 | $8006 | get_byte | none | A=raw byte |
| +9 | $8009 | put_byte | A=raw byte | A=0 |
| +12 | $800c | read | A=count (0=256), XY=buffer | A=0, XY=count transferred |
| +15 | $800f | write | A=count (0=256), XY=buffer | A=0, XY=count transferred |
| +18 | $8012 | status | none | A=state, X=UART LSR, Y=UART MSR |
| +21 | $8015 | set_timeout | A=24-bit high byte, XY=low word | A=0 |
| +24 | $8018 | prepare | none | A=0 |
| +27 | $801b | connect | XY=NUL-terminated ASCII endpoint | A=0 |
| +30 | $801e | disconnect | none | A=0 |
| +33 | $8021 | abi_info | none | A=ABI major 1, XY=$8000 |

The first twelve slots never move within ABI major 1. Future entries may be
appended only with an appropriate layout/version change; existing offsets must
remain stable. At +36: ASCII X16N; +40 major; +41 minor; +42 entry count;
+43 reserved; +44 little-endian binary byte length. Check the magic/header
before trusting an unknown file. abi_info is the minimum callable version query.

## Errors

| A | Name | Meaning |
|---|---|---|
| 0 | OK | Operation succeeded |
| 1 | AGAIN | No byte available, transmitter not ready, or partial block |
| 2 | TIMEOUT | Overall operation poll budget expired |
| 3 | BADARG | Invalid address, length extent, endpoint or zero timeout |
| 4 | NOCARD | Selected UART failed scratch-register probe |
| 5 | STATE | Operation is invalid in the current state |
| 6 | EOF | Network stream carrier absent with no queued UART byte (read), or no carrier (write) |
| 7 | IOERR | UART reports overrun, parity, framing or break |
| 8 | MODEM | prepare received an exact ERROR result |
| 9 | OVERFLOW | Command-result line exceeds 63 bytes |

Block transfers return XY=actual bytes transferred on success or failure.
BADARG returns XY=0 and performs no buffer access. With partial progress, advance
the pointer by XY and reduce the requested count before retrying; never resend
the whole block. On IOERR, the flagged byte is left unread; reinitialize after
diagnosing the transport. No error reporting is inserted into payload bytes.

## States and ownership

0=uninitialized, 1=serial, 2=modem ready, 3=connected, 4=fault/uncertain.

init selects the UART and enters serial state. Raw serial byte/block I/O works
there without network preparation. prepare accepts serial/ready only and enters
ready. connect accepts ready only. disconnect accepts connected/ready, enters
ready, and intentionally discards unread data. EOF keeps state connected so the
caller can explicitly disconnect. status and shutdown also work in fault state;
shutdown is idempotent and clears initialized state.

A timed-out or malformed modem exchange enters fault. Do not assume a timed-out
dial has been cancelled: the ESP32 may still be dialing. Return the modem to a
known idle command state (reset if necessary), then init and prepare again.
Reinitializing UART registers alone does not reset or synchronize the ESP32.

The library is single-instance and non-reentrant. No IRQ handler may call it.
Keep RAM banks and the stack valid during calls. It uses no IRQ hooks and
preserves the caller's interrupt-enable setting. Calls may be interrupted by
normal handlers that do not touch this UART or its library state.

Caller buffers and endpoint strings must live wholly within $0200..$7fff.
The library refuses zero page, the hardware stack, its own code/data, I/O,
banked RAM and ROM. Maximum block size is 256; chunk larger transfers.
Endpoint limit is 95 ASCII bytes plus NUL, with exactly one colon and characters
A-Z/a-z/0-9/dot/hyphen/colon. This is a bounded DNS/IPv4:port format, not IPv6,
a URL parser or full hostname/port validator; invalid ports may time out at the
modem. Input is copied/validated before any dial bytes are sent.

Default entry addresses are fixed, but source can be rebuilt elsewhere.
Such a build must also update the generated bindings, reserved memory and tests;
it is not dynamically relocatable. ABI 1.0 distributed artifacts use $8000 only.

## UART configuration

Port base must be $9f60..$9ff8, aligned to eight bytes. $9fb0/$9fb8 are rejected
because the stock emulator uses that space. Default Wi-Fi UART=$9fe0;
physical RS-232 UART=$9fe8. No broad device scan occurs: init probes only the
explicitly requested UART, restoring its scratch register.

Baud index 0..7 selects 9600,19200,38400,57600,115200,230400,460800,921600.
Divisors are 96,48,24,16,8,4,2,1 for the 14.7456 MHz card oscillator.
init selects 8N1, disables UART interrupts, clears/enables FIFOs and selects
MCR=$27: auto RTS/CTS, DTR/RTS asserted, OPA inactive. shutdown deasserts DTR/RTS.
It does not restore prior UART settings or change the ESP32 baud.

The conservative TX implementation checks THRE before each byte. It does not
fill an entire FIFO burst and does not promise the card's maximum throughput.
No software ring buffer is allocated: block buffers belong to callers, and
hardware FIFO/RTS provide receive backpressure.

## Time budgets

set_timeout accepts 1..$ffffff poll attempts; default is $200000. This bounds the
whole prepare/connect/disconnect exchange, including sending and continuous
noise. It is not milliseconds: CPU clock, code paths and I/O wait states affect
elapsed time. Byte/block I/O is nonblocking; application retry loops must impose
their own wall-clock or idle deadlines. Blocking network control calls do not
yield to an application event loop. Interrupts remain as the caller left them.

## Firmware profile

prepare sends:
    ATE0V1Q0X0F0R0&P0S62=0S63=2S46=0S48=0S50=0S54=0N0H

This selects ASCII commands, no command echo, verbose responses, RTS/CTS,
CR-only responses, no Telnet conversion, DTR hangup, standard handshake polarity,
and closes listeners/connections. It assumes normal ASCII command parsing and
the hardware's normal pin assignment. It does not provision Wi-Fi, write flash,
change saved baud, support alternate modem emulation modes, or reset the ESP32.

connect then sends ATQ1D"endpoint" followed by CR. Responses are suppressed to
avoid modem text in binary data; DCD confirms connection. No +++ escape sequence
is used for hangup. disconnect deasserts DTR until DCD drops, clears the receive
FIFO, and reasserts DTR. On disconnect timeout, DTR stays deasserted and state
becomes fault. Exact pin polarity, modem queue timing and firmware compatibility
are subject to the hardware validation checklist.
