%encoding iso
%import textio
%import diskio
%import x16net
%memtop $8000

main {
    ; Explicit ASCII bytes: do not rely on the target string encoding for wire data.
    ubyte[] request = [71,69,84,32,47,32,72,84,84,80,47,49,46,48,13,10,
                      72,111,115,116,58,32,101,120,97,109,112,108,101,46,
                      99,111,109,13,10,13,10]
    ubyte result
    bool failed

    sub start() {
        ; endpoint below is constructed as ASCII for the same reason.
        ubyte[] address = [101,120,97,109,112,108,101,46,99,111,109,58,56,48,0]
        if diskio.load_raw("x16net.bin", $8000) == 0 {
            txt.print("could not load x16net.bin\n")
            return
        }
        result, failed = x16net.init(4, $9fe0)
        if failed { report() return }
        result, failed = x16net.prepare()
        if failed { report() return }
        result, failed = x16net.connect(&address)
        if failed { report() return }
        ; This demonstration writes a small HTTP/1.0 request. It is not an HTTP parser.
        uword send_idle = 0
        ubyte pos = 0
        do {
            result, failed = x16net.put_byte(request[pos])
            if not failed { pos++ send_idle = 0 }
            else if result != x16net.ERR_AGAIN { report() return }
            else {
                send_idle++
                if send_idle == 0 { txt.print("send idle limit\n") return }
            }
        } until pos == len(request)
        uword idle = 0
        repeat {
            result, failed = x16net.get_byte()
            if not failed {
                idle = 0
                ; A display demonstration only; wire bytes are untranslated.
                txt.chrout(result)
            } else if result == x16net.ERR_EOF {
                break
            } else if result != x16net.ERR_AGAIN {
                report()
                break
            } else {
                idle++
                if idle == 0 { txt.print("\nreceive idle limit\n") break }
            }
        }
        result, failed = x16net.disconnect()
        if failed { report() }
    }
    sub report() {
        txt.print("\nx16net error ")
        txt.print_ub(result)
        txt.print("\n")
    }
}
