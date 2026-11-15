%encoding iso
%import textio
%import diskio
%import x16net
%memtop $8000

; Headless integration test; requires the serial-network emulator.
; The runner patches only the five-digit loopback port in the PRG.
main {
    str endpoint = "127.0.0.1:00000"
    ubyte[256] incoming
    ubyte[256] outgoing
    ubyte[] byte_cases = [0,255,43,13,10,43,43,43]
    ubyte result
    bool failed
    uword transferred
    ubyte state
    ubyte line_status
    ubyte modem_status
    uword test_number = 0

    sub start() {
        @($9fb4) = 0
        if diskio.load_raw("x16net.bin", $8000) == 0 {
            txt.print("# TAP BEGIN\nnot ok 1 - load standalone binary\n1..1\n")
            finish()
        }
        txt.print("# TAP BEGIN\n")
        ubyte version
        uword base
        version, base, failed = x16net.abi_info()
        if failed or version != 1 or base != $8000 { abort() }
        ok("load standalone binary and query ABI")

        result, failed = x16net.init(4, $9fe0)
        if failed { abort() }
        result, failed = x16net.set_timeout($80, 0)
        if failed { abort() }
        result, failed = x16net.prepare()
        if failed { abort() }
        state, line_status, modem_status, failed = x16net.status()
        if failed or state != 2 { abort() }
        ok("initialize UART and prepare modem")

        result, failed = x16net.connect(endpoint)
        if failed { abort() }
        state, line_status, modem_status, failed = x16net.status()
        if failed or state != 3 or modem_status & $80 == 0 { abort() }
        ok("connect through pure Prog8 bindings")

        if not receive_block(&incoming, 256) { abort() }
        ubyte i
        for i in 0 to 255 {
            if incoming[i] != 255-lsb(i) { abort() }
            outgoing[i] = lsb(i)
        }
        ok("preserve immediate binary reply")

        ubyte value
        for value in byte_cases {
            if not send_byte(value) { abort() }
            if not receive_byte(value) { abort() }
        }
        ok("byte I/O preserves NUL FF CR LF and plus escapes")

        repeat 16 {
            if not send_block(&outgoing, 256) { abort() }
            if not receive_block(&incoming, 256) { abort() }
            for i in 0 to 255 {
                if incoming[i] != outgoing[i] { abort() }
            }
        }
        ok("4096 block bytes and partial counts match")

        uword idle = 0
        repeat {
            result, failed = x16net.get_byte()
            if not failed { abort() }
            if result == x16net.ERR_EOF { break }
            if result != x16net.ERR_AGAIN { abort() }
            idle++
            if idle == 0 { abort() }
        }
        ok("EOF follows data without modem trailer")
        result, failed = x16net.disconnect()
        if failed { abort() }
        result, failed = x16net.shutdown()
        if failed { abort() }
        result, failed = x16net.get_byte()
        if not failed or result != x16net.ERR_STATE { abort() }
        ok("disconnect shutdown and state error flags")
        txt.print("1..")
        txt.print_uw(test_number)
        txt.nl()
        finish()
    }

    sub send_byte(ubyte value) -> bool {
        uword idle = 0
        repeat {
            result, failed = x16net.put_byte(value)
            if not failed { return true }
            if result != x16net.ERR_AGAIN { return false }
            idle++
            if idle == 0 { return false }
        }
    }

    sub receive_byte(ubyte expected) -> bool {
        uword idle = 0
        repeat {
            result, failed = x16net.get_byte()
            if not failed { return result == expected }
            if result != x16net.ERR_AGAIN { return false }
            idle++
            if idle == 0 { return false }
        }
    }

    sub send_block(uword address, uword length) -> bool {
        uword done = 0
        uword idle = 0
        while done < length {
            ubyte chunk = if length-done >= 256 then 0 else lsb(length-done)
            result, transferred, failed = x16net.write(chunk, address+done)
            if transferred > length-done { return false }
            done += transferred
            if failed and result != x16net.ERR_AGAIN { return false }
            if transferred != 0 { idle = 0 }
            else {
                idle++
                if idle == 0 { return false }
            }
        }
        return true
    }

    sub receive_block(uword address, uword length) -> bool {
        uword done = 0
        uword idle = 0
        while done < length {
            ubyte chunk = if length-done >= 256 then 0 else lsb(length-done)
            result, transferred, failed = x16net.read(chunk, address+done)
            if transferred > length-done { return false }
            done += transferred
            if failed and result != x16net.ERR_AGAIN { return false }
            if transferred != 0 { idle = 0 }
            else {
                idle++
                if idle == 0 { return false }
            }
        }
        return true
    }

    sub ok(str description) {
        test_number++
        txt.print("ok ")
        txt.print_uw(test_number)
        txt.print(" - ")
        txt.print(description)
        txt.nl()
    }

    sub abort() {
        test_number++
        txt.print("not ok ")
        txt.print_uw(test_number)
        txt.print(" - network integration; result=")
        txt.print_ub(result)
        txt.nl()
        txt.print("1..")
        txt.print_uw(test_number)
        txt.nl()
        finish()
    }

    sub finish() {
        %asm {{ jmp $ffff }}
    }
}
