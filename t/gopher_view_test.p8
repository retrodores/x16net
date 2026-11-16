%encoding iso
%import textio
%import gopher_view
%memtop $8000
main {
    ubyte test
    bool geometry, full_width, selection, no_op, untouched, scroll_up, scroll_down
    bool palette, frame, page_down, page_up, last_page, menu, prompts, empty
    sub start() {
        gview.initialize()
        ubyte width, height
        width, height = txt.size()
        geometry = width == 80 and height == 60
        gopher.kind = '0'
        gopher.count = 100
        gopher.length = 8100
        gopher.terminated = true
        uword i
        ubyte col
        for i in 0 to 99 {
            gopher.lines[lsb(i)] = i*81
            for col in 0 to 78 { @(gopher.page+i*81+col) = 'A'+lsb(i % 26) }
            @(gopher.page+i*81+79) = '0'+lsb(i % 10)
            @(gopher.page+i*81+80) = 10
        }
        gview.new_page()
        full_width = txt.getchr(0, 2) == 'A' and txt.getchr(79, 2) == '0' and
                     txt.getchr(0, 57) == 'D' and txt.getchr(79, 57) == '5'
        txt.setchr(12, 20, '!')
        txt.setclr(12, 20, $ab)
        txt.setchr(79, 59, '#')
        gview.move('?')
        no_op = txt.getchr(79, 59) == '#' and txt.getchr(12, 20) == '!'
        gview.move('j')
        selection = gview.selected == 1 and gview.top == 0 and
                    txt.getclr(79, 2) == gview.NORMAL and txt.getclr(79, 3) == gview.FOCUS
        untouched = txt.getchr(12, 20) == '!' and txt.getclr(12, 20) == $ab
        gview.selected = 55
        gview.refresh()
        gview.move('j')
        scroll_up = gview.top == 1 and txt.getchr(0, 2) == 'B' and
                    txt.getchr(79, 57) == '6' and txt.getchr(12, 19) == '!' and
                    txt.getclr(12, 19) == $ab
        palette = txt.getclr(79, 57) == gview.FOCUS
        for col in 2 to 56 {
            if txt.getclr(79, col) != gview.NORMAL { palette = false }
        }
        gview.selected = 1
        gview.refresh()
        gview.move('k')
        scroll_down = gview.top == 0 and txt.getchr(0, 2) == 'A' and
                      txt.getchr(79, 57) == '5' and txt.getchr(12, 20) == '!' and
                      txt.getclr(12, 20) == $ab
        frame = txt.getchr(0, 0) == 'X' and txt.getchr(0, 1) == 'A' and
                txt.getchr(0, 58) == 'L' and txt.getchr(0, 59) == 'E'
        gview.move('n')
        page_down = gview.selected == 56 and gview.top == 44 and
                    txt.getchr(0, 2) == 'S' and txt.getchr(79, 57) == '9'
        gview.move('n')
        last_page = gview.selected == 99 and gview.top == 44
        gview.move('p')
        page_up = gview.selected == 43 and gview.top == 0
        gview.move(19)
        gview.move(4)
        last_page = last_page and gview.selected == 99 and gview.top == 44

        ; A long header and menu label must fill, but never wrap into another row.
        for col in 0 to 126 { gopher.endpoint[col] = 'E' }
        gopher.endpoint[lsb(127)] = 0
        @(gopher.page) = '1'
        for i in 1 to 110 { @(gopher.page+i) = 'x' }
        @(gopher.page+111) = 9
        @(gopher.page+112) = 10
        gopher.kind = '1'
        gopher.count = 1
        gopher.length = 113
        gopher.lines[lsb(0)] = 0
        gview.new_page()
        menu = txt.getchr(0, 2) == '[' and txt.getchr(1, 2) == '1' and
               txt.getchr(4, 2) == 'x' and txt.getchr(79, 2) == 'x' and
               txt.getchr(0, 3) == 32 and txt.getchr(0, 1) == 'A'
        gview.busy("Loading...")
        prompts = txt.getchr(79, 2) == 'x' and txt.getchr(0, 0) == 'X'
        gview.input_echo(&gopher.endpoint, 127)
        prompts = prompts and txt.getchr(0, 59) == '>' and txt.getchr(78, 59) == '_' and
                  txt.getchr(0, 0) == 'X' and txt.getchr(79, 2) == 'x'
        gopher.count = 0
        gopher.length = 0
        gview.new_page()
        empty = gview.selected == 0 and gview.top == 0 and
                txt.getchr(79, 57) == 32 and txt.getclr(0, 2) == gview.NORMAL

        txt.plot(0, 0)
        txt.print("\n# GOPHER DISPLAY TAP BEGIN\n")
        check(geometry, "X16 80x60 screen")
        check(full_width, "56 content rows include all 80 columns")
        check(selection, "selection moves by changing only row colors")
        check(no_op, "unrecognized key performs no repaint")
        check(untouched, "cursor movement preserves unrelated screen cells")
        check(scroll_up, "up scroll copies characters and colors and draws exposed row")
        check(scroll_down, "down scroll is overlap safe and includes final column")
        check(palette, "scroll leaves exactly one highlighted row")
        check(frame, "scroll preserves fixed header and footer")
        check(page_down, "page down advances the viewport and clamps its bottom")
        check(page_up, "page up returns to the previous viewport")
        check(last_page, "last partial page and Home/End remain reachable")
        check(menu, "long menu labels and host names cannot wrap")
        check(prompts, "loading and long input keep the page visible")
        check(empty, "empty page clears stale content without underflow")
        txt.print("1..15\n")
        %asm {{ jmp $ffff }}
    }
    sub check(bool okay, str label) {
        test++
        if okay { txt.print("ok ") } else { txt.print("not ok ") }
        txt.print_ub(test)
        txt.print(" - ")
        txt.print(label)
        txt.nl()
    }
}
