# Prog8 usage

The compiled binary has no Prog8 runtime dependency. prog8/x16net.p8 is a thin
set of generated extsub declarations, including carry-flag error results.
Return registers must not also appear in an extsub clobber list.

Compile with:
    prog8c -target cx16 -out build -srcdirs prog8 examples/connect.p8

Reserve the library's memory using %memtop $8000 in the caller. Load it with
diskio.load_raw("x16net.bin", $8000), checking the returned end address for zero.
Use %encoding iso for ASCII strings, or construct wire bytes explicitly as in
the example. Do not silently translate application data to PETSCII.

Typical sequence:
    result, failed = x16net.init(4, $9fe0)
    result, failed = x16net.prepare()
    result, failed = x16net.connect(&endpoint_bytes)

Check failed after EVERY call; the sequence above is a calling-signature sketch.
get_byte returns data in result on success, while put_byte returns zero.
ERR_AGAIN means retry later. ERR_EOF is distinct from AGAIN and TIMEOUT.

Block read/write return:
    result, transferred, failed = x16net.read(count, buffer_address)

count is ubyte: zero requests 256 bytes, not an empty operation. transferred is
uword, so it can represent 256. On partial transfer, continue at buffer_address
+ transferred with the remaining byte count. The routine never copies data to
a hidden terminal buffer or renders it.

The example sends a minimal HTTP/1.0 request then displays response bytes. It does
not parse status, redirects, headers, Content-Length or chunked encoding.
It has bounded retry loops so a stalled peer cannot hang the demonstration.
A real client should provide its own timer/event loop and protocol parsing.

For Gopher, connect to host:70 and send selector followed by CR LF. Parse menus
and text terminators in application code; never have the transport strip dots,
tabs, CR LF or bytes that resemble modem messages.

The network UART is $9fe0 by default. init(4,$9fe8) instead selects the physical
serial port; raw byte/block functions can use it without prepare/connect.
