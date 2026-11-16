%encoding iso
%import textio
%import syslib
%import gopher_client
%memtop $8000

; Small Gopher browser using only the pure x16net bindings.
; Serial reference credits: David Murray's ROMTERM and TexElec's card.
; https://texelec.com/product/commander-x16-serial-network-card/
main {
    uword selected=0
    uword top=0
    ubyte depth=0
    uword history = memory("gopher_history", 3080, 0)
    ubyte[128] input

    sub start() {
        txt.iso()
        txt.clear_screen()
        txt.print("X16NET GOPHER\n\nInitializing serial card at $9FE0...\n")
        if not gopher.initialize() { error() void txt.waitkey() return }
        void gopher.copy(&gopher.endpoint,"gopher.floodgap.com:70",128)
        gopher.selector[lsb(0)]=0
        if not location() { shutdown() return }
        fetch()
        repeat {
            draw()
            ubyte key=txt.waitkey()
            when key {
                'q','Q' -> break
                'g','G' -> { if location() { depth=0 fetch() } }
                'r','R' -> fetch()
                'b','B',157 -> { if depth>0 { history_pop() fetch() } }
                17,'j' -> { if selected+1<gopher.count { selected++ } }
                145,'k' -> { if selected>0 { selected-- } }
                'n',' ' -> { if selected+20<gopher.count { selected+=20 } }
                'p' -> { if selected>=20 { selected-=20 } else { selected=0 } }
                13 -> open_item()
            }
        }
        shutdown()
    }
    sub shutdown() {
        gopher.close()
        gopher.status,gopher.failed=x16net.shutdown()
        txt.clear_screen()
    }
    sub input_line(ubyte maximum) -> bool {
        ubyte size=0
        input[lsb(0)]=0
        repeat {
            ubyte key=txt.waitkey()
            if key==27 { return false }
            if key==13 { input[lsb(size)]=0 txt.nl() return true }
            if key==20 or key==8 {
                if size>0 { size-- txt.chrout(20) }
            } else if key>=32 and key<=126 and size<maximum {
                input[lsb(size)]=key size++ txt.chrout(key)
            }
        }
    }
    sub location() -> bool {
        txt.clear_screen()
        txt.print("X16NET GOPHER\n\nHost:port [") txt.print(&gopher.endpoint) txt.print("]\n")
        txt.print("Enter keeps current host; Esc cancels.\n> ")
        if not input_line(120) { return false }
        if input[lsb(0)]!=0 { void gopher.copy(&gopher.endpoint,&input,128) }
        txt.print("Selector (Enter for root):\n> ")
        if not input_line(127) { return false }
        void gopher.copy(&gopher.selector,&input,256)
        gopher.kind='1'
        return true
    }
    sub fetch() {
        txt.clear_screen() txt.print("Loading ") txt.print(&gopher.endpoint) txt.print("... Esc cancels.\n")
        if not gopher.fetch() { error() void txt.waitkey() }
        selected=0 top=0
    }
    sub error() {
        txt.print("\nError ") txt.print_ub(gopher.status)
        txt.print(". Check the host, serial card and connection.\n")
    }
    sub draw() {
        if selected<top { top=selected }
        if selected>=top+20 { top=selected-19 }
        txt.clear_screen()
        txt.print("X16NET GOPHER | ") txt.print(&gopher.endpoint) txt.nl()
        txt.print("Arrows/j/k: move  Enter: open  B: back  G: go  R: reload  Q: quit\n")
        txt.print("N/Space: next page  P: previous page\n\n")
        uword row=top
        repeat 20 {
            if row<gopher.count {
                if row==selected { txt.print("> ") } else { txt.print("  ") }
                if gopher.kind=='1' or gopher.kind=='7' {
                    txt.chrout('[') safe(@(gopher.page+gopher.lines[lsb(row)])) txt.print("] ")
                }
                uword position=gopher.lines[lsb(row)]
                if gopher.kind=='1' or gopher.kind=='7' { position++ }
                ubyte column=0
                while position<gopher.length and column<72 {
                    ubyte ch=@(gopher.page+position)
                    if ch==10 or (gopher.kind=='1' or gopher.kind=='7') and ch==9 { break }
                    safe(ch) column++ position++
                }
                txt.rvs_off()
            }
            txt.nl() row++
        }
        txt.print("Line ") txt.print_uw(selected+1) txt.chrout('/') txt.print_uw(gopher.count)
        if gopher.truncated { txt.print("  [preview limit: 8 KiB / 256 lines]") }
        else if not gopher.terminated { txt.print("  [server ended without final dot]") }
        txt.nl()
    }
    sub safe(ubyte ch) {
        if ch==9 { txt.spc() }
        else if ch>=32 and ch<=126 { txt.chrout(ch) }
        else { txt.chrout('?') }
    }
    sub history_push() {
        if depth==8 {
            uword i
            for i in 0 to 2694 { @(history+i)=@(history+i+385) }
            depth=7
        }
        uword where=depth*385
        void gopher.copy(history+where,&gopher.endpoint,128)
        void gopher.copy(history+where+128,&gopher.selector,256)
        @(history+where+384)=gopher.kind
        depth++
    }
    sub history_pop() {
        depth--
        uword where=depth*385
        void gopher.copy(&gopher.endpoint,history+where,128)
        void gopher.copy(&gopher.selector,history+where+128,256)
        gopher.kind=@(history+where+384)
    }
    sub open_item() {
        if gopher.kind not in ['1','7'] { return }
        if not gopher.target(selected) {
            txt.print("\nInformational, unsupported or malformed item. Press a key.")
            void txt.waitkey() return
        }
        if gopher.next_kind=='7' {
            txt.print("\nSearch: ")
            if not input_line(100) { return }
            uword size=0
            while gopher.next_selector[lsb(size)]!=0 { size++ }
            uword n=0
            while input[lsb(n)]!=0 { n++ }
            if size+n+1>255 { txt.print("Search is too long.") void txt.waitkey() return }
            gopher.next_selector[lsb(size)]=9
            void gopher.copy(&gopher.next_selector+size+1,&input,256-size-1)
        }
        if gopher.next_kind in ['0','1','7'] { history_push() gopher.use_target() fetch() return }
        txt.print("\nSave binary as a NEW file (letters, digits, ._-; max 31):\n> ")
        if not input_line(31) or input[lsb(0)]==0 { return }
        ubyte i=0
        while input[lsb(i)]!=0 {
            ubyte c=input[lsb(i)]
            if not (c>='a' and c<='z' or c>='A' and c<='Z' or c>='0' and c<='9' or c in ['.','_','-']) {
                txt.print("Invalid filename.") void txt.waitkey() return
            }
            i++
        }
        history_push() gopher.use_target()
        txt.print("Downloading... Esc cancels.\n")
        if gopher.download(&input) { txt.print("Download complete.\n") }
        else { error() txt.print("A partial file may remain.\n") }
        void txt.waitkey()
        history_pop() fetch()
    }
}
