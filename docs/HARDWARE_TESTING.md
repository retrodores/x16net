# Physical-card acceptance checklist

Status: NOT RUN. The development VM has no physical serial/network card.
Record ROM version, card revision, jumper/DIP configuration, installed Zimodem
ATI version, baud, server fixture, payload hash and failures for each run.

1. Before running the library, verify ROMTERM can issue ATI/AT+CONFIG and Wi-Fi
   works. Configure 115200 and RTS/CTS; leave normal ASCII command mode.
2. Load bin/x16net.bin at $8000. Check ABI/header, init(4,$9fe0), then prepare.
   Confirm only the selected UART changes and no screen/bank/IRQ state is changed.
3. Check DTR/RTS, DCD/CTS and OPA levels against the actual card. Verify MCR=$27
   and the standard Zimodem handshake profile. Confirm the $2b configuration in
   the friend's experiment is not needed for this card/firmware revision.
4. Connect to a controlled TCP echo fixture. Send all 256 byte values repeatedly,
   including NUL, $11/$13, +++, ESC sequences, CR/LF, $ff and modem-like text.
   Compare byte counts and SHA-256 at each end. No translation or echo is allowed.
5. Exercise single bytes, 1/15/16/17/255/256-byte blocks, page crossings, slow
   receivers, paused callers and prolonged CTS stalls. Verify no FIFO overruns.
6. Test immediate server data, empty reply, server close immediately after data,
   slow final bytes and closed ports. Specifically determine whether DCD may
   drop before ESP32 serial queues drain; current EOF does not account for hidden
   firmware queues. Verify full HTTP Content-Length/hash rather than trusting EOF.
7. Verify Q1 suppresses CONNECT and NO CARRIER completely. A payload containing
   those strings must pass unchanged. Determine whether firmware still emits any
   unsolicited notices while quiet. Check the upstream AT&G binary warning
   separately; x16net does not use AT&G.
8. Disconnect while receiving and while idle. Ensure DTR closes only the owned
   session and reconnects repeatedly. A stuck carrier must return TIMEOUT and
   leave DTR deasserted. A dial timeout requires restoring known modem state.
9. Repeat at the eight supported rates, changing ESP32 baud separately. Measure
   throughput; do not infer 921600 throughput from register configuration.
10. Raw serial on $9fe8 needs a separate peer, proper cabling and compatible
    handshakes. Confirm UART IRQ enable remains zero.
11. Record real poll-budget durations at the CPU clock in use. Application
    transfer deadlines must remain bounded and responsive to cancellation.

A failure requires a regression fixture in t/ and a rerun on hardware.
A model-test pass alone must never change this document's NOT RUN status.
