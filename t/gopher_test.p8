%encoding iso
%import textio
%import gopher_client
%memtop $8000
main {
    str address="127.0.0.1:00000"
    ubyte test=0
    sub start() {
        txt.iso()
        bool ready=gopher.initialize()
        txt.print("\n# GOPHER TAP BEGIN\n")
        check(ready,"load library and prepare")
        void gopher.copy(&gopher.endpoint,address,128)
        gopher.selector[lsb(0)]=0
        check(gopher.fetch(),"root menu transfer")
        check(gopher.count==6 and gopher.terminated and not gopher.truncated,"menu boundaries")
        check(gopher.target(0) and gopher.next_kind=='0',"menu text target")
        gopher.use_target()
        check(gopher.fetch() and gopher.length==11 and @(gopher.page+0)=='.' and @(gopher.page+4)==10,"text CRLF and dot unescaping")
        void gopher.copy(&gopher.selector,"/search\x09needle",256)
        gopher.kind='7'
        check(gopher.fetch() and gopher.count==1 and gopher.target(0),"search query and result menu")
        gopher.use_target()
        check(gopher.download("gopher-test.bin"),"stream exact binary to disk")
        check(not gopher.download("gopher-test.bin") and gopher.status==67,"existing file is not overwritten")
        void gopher.copy(&gopher.selector,"/wide",256)
        gopher.kind='0'
        check(gopher.fetch() and gopher.count==3 and gopher.lines[lsb(1)]==81 and gopher.lines[lsb(2)]==161,"text uses all 80 columns without extra wrapped rows")
        void gopher.copy(&gopher.selector,"/large",256)
        gopher.kind='0'
        check(gopher.fetch() and gopher.truncated and gopher.length<=8192,"oversized page is bounded")
        void gopher.copy(&gopher.selector,"/missing-dot",256)
        check(gopher.fetch() and not gopher.terminated,"unterminated response is identified")
        void gopher.copy(&gopher.selector,"/bad-menu",256)
        gopher.kind='1'
        check(gopher.fetch() and not gopher.target(0) and not gopher.target(1) and not gopher.target(2),"malformed targets rejected")
        gopher.close()
        txt.print("1..12\n")
        %asm {{ jmp $ffff }}
    }
    sub check(bool okay,str label) {
        test++
        if okay { txt.print("ok ") } else { txt.print("not ok ") }
        txt.print_ub(test) txt.print(" - ") txt.print(label) txt.nl()
        if not okay { txt.print("# status ") txt.print_ub(gopher.status) txt.nl() }
    }
}
