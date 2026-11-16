; X16-only 80x60 renderer. VERA rows use a 256-byte map stride and
; two bytes per cell. Inspired by XVI2 and p8vi's incremental renderers;
; these bounded routines also move colors so selection never leaves trails.
%encoding iso
%import textio
%import syslib
%import gopher_client

gview {
    const ubyte WIDTH = 80
    const ubyte FIRST = 2
    const ubyte LAST = 57
    const ubyte HEIGHT = 56
    const ubyte NORMAL = $07
    const ubyte FOCUS = $70
    const ubyte CHROME = $0f
    uword selected
    uword top
    uword drawn_selected
    uword drawn_top
    bool invalid = true
    ubyte[80] @shared rowbuf
    ubyte column

    sub initialize() {
        cx16.set_screen_mode(0)
        txt.iso()
        txt.color2(7, 0)
        txt.fill_screen(32, NORMAL)
        selected = 0
        top = 0
        invalid = true
        header()
        message("Initializing serial card at $9FE0...", false)
    }

    sub clear_buffer() {
        sys.memset(&rowbuf, WIDTH, 32)
        column = 0
    }

    sub append(ubyte value) {
        if column < WIDTH {
            if value < 32 or value > 126 { value = '?' }
            rowbuf[column] = value
            column++
        }
    }

    sub text(uword source) {
        uword i = 0
        while column < WIDTH and @(source+i) != 0 {
            append(@(source+i))
            i++
        }
    }

    sub number(uword value) {
        uword divisor = 10000
        bool leading = true
        repeat 5 {
            ubyte digit = (value / divisor) as ubyte
            value = value % divisor
            if digit != 0 or not leading or divisor == 1 {
                append('0'+digit)
                leading = false
            }
            divisor = divisor / 10
        }
    }

    sub header() {
        clear_buffer()
        text("X16NET GOPHER | ")
        text(&gopher.endpoint)
        write_row(0, CHROME)
        clear_buffer()
        text("Arrows/j/k Move  Enter Open  N/P Page  B Back  G Go  R Reload  Q Quit")
        write_row(1, CHROME)
    }

    sub footer() {
        clear_buffer()
        text("Line ")
        if gopher.count == 0 { number(0) } else { number(selected+1) }
        append('/')
        number(gopher.count)
        text("  |  56 rows")
        if gopher.truncated { text("  |  Preview limit: 8 KiB / 256 lines") }
        else if not gopher.terminated and gopher.count > 0 { text("  |  Missing final dot") }
        write_row(58, CHROME)
        message("Esc cancels a prompt or transfer.  Home/End: first/last line.", true)
    }

    sub message(str label, bool second) {
        clear_buffer()
        text(label)
        if second { write_row(59, CHROME) } else { write_row(58, CHROME) }
    }

    sub busy(str label) {
        message(label, false)
        message("Esc cancels. The current page stays visible until the transfer finishes.", true)
    }

    sub render_row(ubyte screen_row, uword index) {
        clear_buffer()
        if index < gopher.count {
            uword position = gopher.lines[lsb(index)]
            bool menu = gopher.kind == '1' or gopher.kind == '7'
            if menu {
                append('[')
                append(@(gopher.page+position))
                text("] ")
                position++
            }
            while position < gopher.length and column < WIDTH {
                ubyte ch = @(gopher.page+position)
                if ch == 10 or menu and ch == 9 { break }
                if ch == 9 { ch = 32 }
                append(ch)
                position++
            }
        }
        write_row(screen_row, NORMAL)
    }

    sub new_page() {
        selected = 0
        top = 0
        invalid = true
        refresh()
    }

    sub refresh() {
        if gopher.count == 0 { selected = 0 top = 0 }
        else {
            selected = min(selected, gopher.count-1)
            if selected < top { top = selected }
            if selected >= top+HEIGHT { top = selected-HEIGHT+1 }
            if gopher.count > HEIGHT { top = min(top, gopher.count-HEIGHT) }
            else { top = 0 }
        }
        if not invalid and selected == drawn_selected and top == drawn_top { return }
        sys.waitvsync()
        ubyte row
        ubyte delta
        if invalid {
            header()
            for row in FIRST to LAST { render_row(row, top+row-FIRST) }
        } else {
            if drawn_selected >= drawn_top and drawn_selected < drawn_top+HEIGHT {
                color_row((FIRST+drawn_selected-drawn_top) as ubyte, NORMAL)
            }
            if top > drawn_top and top-drawn_top <= 4 {
                delta = (top-drawn_top) as ubyte
                for row in FIRST to LAST-delta { copy_row(row+delta, row) }
                for row in LAST-delta+1 to LAST { render_row(row, top+row-FIRST) }
            } else if top < drawn_top and drawn_top-top <= 4 {
                delta = (drawn_top-top) as ubyte
                row = LAST
                while row >= FIRST+delta {
                    copy_row(row-delta, row)
                    row--
                }
                for row in FIRST to FIRST+delta-1 { render_row(row, top+row-FIRST) }
            } else if top != drawn_top {
                for row in FIRST to LAST { render_row(row, top+row-FIRST) }
            }
        }
        if gopher.count > 0 {
            color_row((FIRST+selected-top) as ubyte, FOCUS)
        }
        drawn_selected = selected
        drawn_top = top
        invalid = false
        footer()
    }

    sub move(ubyte key) {
        if gopher.count == 0 { return }
        when key {
            17, 'j' -> { if selected+1 < gopher.count { selected++ } }
            145, 'k' -> { if selected > 0 { selected-- } }
            'n', 'N', ' ' -> {
                selected = min(selected+HEIGHT, gopher.count-1)
                top += HEIGHT
            }
            'p', 'P' -> {
                if top >= HEIGHT { top -= HEIGHT } else { top = 0 }
                if selected >= HEIGHT { selected -= HEIGHT }
                else { selected = 0 }
            }
            19 -> selected = 0
            4 -> selected = gopher.count-1
        }
        refresh()
    }

    sub input_echo(uword source, ubyte size) {
        clear_buffer()
        text("> ")
        ubyte first = 0
        if size > 76 { first = size-76 }
        text(source+first)
        if column < WIDTH { append('_') }
        write_row(59, CHROME)
    }

    ; Complete rows never pass through CHROUT, so column 79 cannot wrap.
    asmsub write_row(ubyte row @Y, ubyte colors @A) clobbers(A, X, Y) {
        %asm {{
            sta  P8ZP_SCRATCH_B1
            stz  cx16.VERA_CTRL
            stz  cx16.VERA_ADDR_L
            tya
            clc
            adc  #>txt.VERA_TEXTMATRIX
            sta  cx16.VERA_ADDR_M
            lda  #(txt.VERA_TEXTMATRIX >> 16) | $10
            sta  cx16.VERA_ADDR_H
            ldx  #0
-           lda  p8b_gview.p8v_rowbuf,x
            sta  cx16.VERA_DATA0
            lda  P8ZP_SCRATCH_B1
            sta  cx16.VERA_DATA0
            inx
            cpx  #80
            bne  -
            rts
        }}
    }

    asmsub color_row(ubyte row @Y, ubyte colors @A) clobbers(A, X, Y) {
        %asm {{
            pha
            stz  cx16.VERA_CTRL
            lda  #1
            sta  cx16.VERA_ADDR_L
            tya
            clc
            adc  #>txt.VERA_TEXTMATRIX
            sta  cx16.VERA_ADDR_M
            lda  #(txt.VERA_TEXTMATRIX >> 16) | $20
            sta  cx16.VERA_ADDR_H
            pla
            ldx  #80
-           sta  cx16.VERA_DATA0
            dex
            bne  -
            rts
        }}
    }

    ; Copy in the caller's overlap-safe row order. Both text and colors move.
    asmsub copy_row(ubyte source @Y, ubyte destination @X) clobbers(A, X, Y) {
        %asm {{
            stz  cx16.VERA_CTRL
            stz  cx16.VERA_ADDR_L
            tya
            clc
            adc  #>txt.VERA_TEXTMATRIX
            sta  cx16.VERA_ADDR_M
            lda  #(txt.VERA_TEXTMATRIX >> 16) | $10
            sta  cx16.VERA_ADDR_H
            lda  #1
            sta  cx16.VERA_CTRL
            stz  cx16.VERA_ADDR_L
            txa
            clc
            adc  #>txt.VERA_TEXTMATRIX
            sta  cx16.VERA_ADDR_M
            lda  #(txt.VERA_TEXTMATRIX >> 16) | $10
            sta  cx16.VERA_ADDR_H
            ; Eight bytes per iteration: less branch overhead while preserving
            ; both bytes of every cell (20 * 8 = 160 bytes per visible row).
            ldx  #20
-           .rept 8
            lda  cx16.VERA_DATA0
            sta  cx16.VERA_DATA1
            .endrept
            dex
            bne  -
            stz  cx16.VERA_CTRL
            rts
        }}
    }
}
