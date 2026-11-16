%encoding iso
%import textio
%import syslib
%import gopher_view
%memtop $8000

; X16-only Gopher browser using the standalone x16net binary.
; Serial reference credits: David Murray's ROMTERM and TexElec's card.
; https://texelec.com/product/commander-x16-serial-network-card/
main {
    bool network_ready = false
    ubyte depth = 0
    uword history = memory("gopher_history", 3080, 0)
    ubyte[128] input
    ubyte[128] pending_endpoint

    sub start() {
        void gopher.copy(&gopher.endpoint, "gopher.floodgap.com:70", 128)
        gview.initialize()
        if not gopher.initialize() {
            error()
            void txt.waitkey()
            shutdown()
            return
        }
        network_ready = true
        gopher.selector[lsb(0)] = 0
        if not location() { shutdown() return }
        fetch()
        repeat {
            ubyte key = txt.waitkey()
            when key {
                'q', 'Q' -> break
                'g', 'G' -> { if location() { depth = 0 fetch() } }
                'r', 'R' -> fetch()
                'b', 'B', 157 -> { if depth > 0 { history_pop() fetch() } }
                13 -> open_item()
                else -> gview.move(key)
            }
        }
        shutdown()
    }

    sub shutdown() {
        if network_ready {
            gopher.close()
            gopher.status, gopher.failed = x16net.shutdown()
        }
        txt.clear_screen()
        txt.iso_off()
    }

    sub input_line(ubyte maximum) -> bool {
        ubyte size = 0
        input[lsb(0)] = 0
        gview.input_echo(&input, size)
        repeat {
            ubyte key = txt.waitkey()
            if key == 27 { gview.footer() return false }
            if key == 13 { return true }
            if key == 20 or key == 8 {
                if size > 0 { size-- }
            } else if key >= 32 and key <= 126 and size < maximum {
                input[lsb(size)] = key
                size++
            }
            input[lsb(size)] = 0
            gview.input_echo(&input, size)
        }
    }

    sub valid_endpoint(uword source) -> bool {
        ubyte i = 0
        ubyte c
        while @(source+i) != 0 and @(source+i) != ':' {
            c = @(source+i)
            if not (c >= 'a' and c <= 'z' or c >= 'A' and c <= 'Z' or
                    c >= '0' and c <= '9' or c in ['-', '.']) { return false }
            i++
            if i >= 94 { return false }
        }
        if i == 0 or @(source+i) != ':' { return false }
        i++
        uword port = 0
        ubyte digits = 0
        while @(source+i) != 0 {
            c = @(source+i)
            if c < '0' or c > '9' or digits == 5 { return false }
            if port > 6553 or port == 6553 and c > '5' { return false }
            port = port*10 + (c-'0')
            digits++
            i++
        }
        return port > 0 and digits > 0 and i <= 95
    }

    sub location() -> bool {
        repeat {
            gview.message("Host:port only, e.g. sdf.org:70 (Enter keeps current; Esc cancels):", false)
            if not input_line(95) { return false }
            if input[lsb(0)] == 0 {
                void gopher.copy(&pending_endpoint, &gopher.endpoint, 128)
                break
            }
            if valid_endpoint(&input) {
                void gopher.copy(&pending_endpoint, &input, 128)
                break
            }
            notice("Use host:port with no URL or /path. Enter the selector separately.")
        }
        gview.message("Selector (Enter for root; Esc cancels):", false)
        if not input_line(127) { return false }
        void gopher.copy(&gopher.endpoint, &pending_endpoint, 128)
        void gopher.copy(&gopher.selector, &input, 256)
        gopher.kind = '1'
        return true
    }

    sub fetch() {
        gview.busy("Loading... Esc cancels.")
        bool okay = gopher.fetch()
        gview.new_page()
        if not okay {
            error()
            void txt.waitkey()
            gview.footer()
        }
    }

    sub error() {
        when gopher.status {
            2, 65 -> gview.message("Timed out waiting for the server. Check the host and connection.", false)
            3 -> gview.message("Invalid host:port. Use sdf.org:70; enter the selector separately.", false)
            4 -> gview.message("Serial card not found. Start the emulator with -serialcard.", false)
            5 -> gview.message("Modem is not ready. Restart the client and check the connection.", false)
            64 -> gview.message("Cannot load x16net.bin. Put the matching binary beside this PRG.", false)
            66 -> gview.message("Transfer cancelled.", false)
            67 -> gview.message("Cannot create file. Choose a NEW filename; existing files are protected.", false)
            68 -> gview.message("Download exceeded the 1 MiB limit.", false)
            else -> gview.message("Transfer failed. Check the host, serial card and connection.", false)
        }
        gview.message("Press a key to continue.", true)
    }

    sub notice(str label) {
        gview.message(label, false)
        gview.message("Press a key to continue.", true)
        void txt.waitkey()
        gview.footer()
    }

    sub history_push() {
        if depth == 8 {
            uword i
            for i in 0 to 2694 { @(history+i) = @(history+i+385) }
            depth = 7
        }
        uword where = depth*385
        void gopher.copy(history+where, &gopher.endpoint, 128)
        void gopher.copy(history+where+128, &gopher.selector, 256)
        @(history+where+384) = gopher.kind
        depth++
    }

    sub history_pop() {
        depth--
        uword where = depth*385
        void gopher.copy(&gopher.endpoint, history+where, 128)
        void gopher.copy(&gopher.selector, history+where+128, 256)
        gopher.kind = @(history+where+384)
    }

    sub open_item() {
        if gopher.kind not in ['1', '7'] { return }
        if not gopher.target(gview.selected) {
            notice("Informational, unsupported or malformed item.")
            return
        }
        if gopher.next_kind == '7' {
            gview.message("Search (Esc cancels):", false)
            if not input_line(100) { return }
            uword size = 0
            while gopher.next_selector[lsb(size)] != 0 { size++ }
            uword n = 0
            while input[lsb(n)] != 0 { n++ }
            if size+n+1 > 255 { notice("Search is too long.") return }
            gopher.next_selector[lsb(size)] = 9
            void gopher.copy(&gopher.next_selector+size+1, &input, 256-size-1)
        }
        if gopher.next_kind in ['0', '1', '7'] {
            history_push()
            gopher.use_target()
            fetch()
            return
        }
        gview.message("Save as a NEW file (letters, digits, ._-; max 31; Esc cancels):", false)
        if not input_line(31) or input[lsb(0)] == 0 { gview.footer() return }
        ubyte i = 0
        while input[lsb(i)] != 0 {
            ubyte c = input[lsb(i)]
            if not (c >= 'a' and c <= 'z' or c >= 'A' and c <= 'Z' or
                    c >= '0' and c <= '9' or c in ['.', '_', '-']) {
                notice("Invalid filename.")
                return
            }
            i++
        }
        history_push()
        gopher.use_target()
        gview.busy("Downloading... Esc cancels.")
        if gopher.download(&input) { notice("Download complete.") }
        else {
            error()
            gview.message("A partial file may remain. Press a key to continue.", true)
            void txt.waitkey()
        }
        history_pop()
        fetch()
    }
}
