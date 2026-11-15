%encoding iso
%import textio
%import diskio
%import x16net
%memtop $8000

main {
    sub finish() {
        @($9fb4) = 0
        %asm {{ jmp $ffff }}
    }
    sub start() {
        ubyte version
        uword base
        bool failed
        if diskio.load_raw("x16net.bin", $8000) == 0 {
            txt.print("# TAP BEGIN\n")
            txt.print("not ok 1 - load binary\n1..1\n")
            finish()
            return
        }
        txt.print("# TAP BEGIN\n")
        version, base, failed = x16net.abi_info()
        if version == 1 and base == $8000 and not failed {
            txt.print("ok 1 - external binary ABI\n")
        } else {
            txt.print("# TAP BEGIN\n")
            txt.print("not ok 1 - external binary ABI\n")
        }
        ubyte result
        result, failed = x16net.get_byte()
        if failed and result == x16net.ERR_STATE {
            txt.print("ok 2 - uninitialized carry return\n")
        } else {
            txt.print("not ok 2 - uninitialized carry return\n")
        }
        txt.print("1..2\n")
        finish()
    }
}
