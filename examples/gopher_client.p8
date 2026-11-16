; Gopher protocol core shared by the demo and its emulator tests.
; RFC 1436. Wire strings use ISO/ASCII, independently of display rendering.
%import x16net
%import diskio
%import syslib

gopher {
    const uword CAPACITY = 8192
    ubyte[128] endpoint
    ubyte[256] selector
    uword page = memory("gopher_page", 8193, 0)
    uword[256] lines
    uword length
    uword count
    ubyte kind = '1'
    ubyte status
    bool failed
    bool truncated
    bool terminated
    uword started
    uword last_byte
    ubyte[128] next_endpoint
    ubyte[256] next_selector
    ubyte next_kind
    uword field_end
    uword line_end

    sub initialize() -> bool {
        if diskio.load_raw("x16net.bin", $8000) == 0 { status=64 return false }
        status, failed = x16net.init(4, $9fe0)
        if failed { return false }
        status, failed = x16net.set_timeout($80, 0)
        if failed { return false }
        status, failed = x16net.prepare()
        return not failed
    }

    sub copy(uword destination, uword source, uword capacity) -> bool {
        uword i=0
        while i<capacity-1 {
            @(destination+i)=@(source+i)
            if @(source+i)==0 { return true }
            i++
        }
        @(destination+i)=0
        return @(source+i)==0
    }

    sub put(ubyte value) -> bool {
        uword since=cbm.RDTIM16()
        repeat {
            status, failed = x16net.put_byte(value)
            if not failed { return true }
            if status!=x16net.ERR_AGAIN { return false }
            if cbm.RDTIM16()-since>1800 { status=65 return false }
            if cbm.GETIN2()==27 { status=66 return false }
        }
    }

    sub get() -> bool {
        repeat {
            if cbm.RDTIM16()-started>18000 { status=65 return false }
            if cbm.GETIN2()==27 { status=66 return false }
            status, failed = x16net.get_byte()
            if not failed { last_byte=cbm.RDTIM16() return true }
            if status!=x16net.ERR_AGAIN { return false }
            if cbm.RDTIM16()-last_byte>1800 or cbm.RDTIM16()-started>18000 {
                status=65 return false
            }
            if cbm.GETIN2()==27 { status=66 return false }
        }
    }

    sub begin() -> bool {
        status, failed = x16net.connect(&endpoint)
        if failed { return false }
        started=cbm.RDTIM16()
        last_byte=started
        uword i=0
        while selector[lsb(i)]!=0 {
            if not put(selector[lsb(i)]) { close() return false }
            i++
        }
        if not put(13) or not put(10) { close() return false }
        return true
    }

    sub close() {
        ubyte ignored
        bool ignored_failed
        ignored, ignored_failed = x16net.disconnect()
    }

    sub fetch() -> bool {
        length=0 count=0 truncated=false terminated=false
        if not begin() { return false }
        while get() {
            if length==CAPACITY { truncated=true break }
            @(page+length)=status
            length++
        }
        close()
        if not truncated and status!=x16net.ERR_EOF { return false }
        ; Strip CR, remove dot-stuffing, and stop at the protocol terminator.
        ; Only text/menu responses come through this routine; downloads stay raw.
        uword source=0
        uword destination=0
        bool start_line=true
        while source<length {
            if start_line and @(page+source)=='.' {
                if source+1<length and @(page+source+1)=='.' { source++ }
                else if source+1<length and @(page+source+1) in [13,10] {
                    terminated=true break
                }
            }
            ubyte value=@(page+source)
            source++
            if value!=13 {
                @(page+destination)=value
                destination++
                start_line=value==10
            }
        }
        length=destination
        @(page+length)=0
        if length>0 {
            lines[lsb(0)]=0 count=1
            uword i
            ubyte column=0
            for i in 0 to length-1 {
                column++
                bool next_line=@(page+i)==10
                if kind=='0' and column==72 and i+1<length and @(page+i+1)!=10 { next_line=true }
                if next_line {
                    column=0
                    if i+1<length {
                        if count<256 { lines[lsb(count)]=i+1 count++ }
                        else { truncated=true break }
                    }
                }
            }
        }
        status=0
        return true
    }

    sub field(uword start, uword destination, uword capacity) -> bool {
        uword i=0
        while start<line_end and @(page+start)!=9 {
            if i>=capacity-1 or @(page+start)<32 or @(page+start)>126 { return false }
            @(destination+i)=@(page+start)
            i++ start++
        }
        @(destination+i)=0
        field_end=start
        return true
    }

    sub target(uword selected) -> bool {
        if selected>=count { return false }
        uword start=lines[lsb(selected)]
        next_kind=@(page+start)
        if next_kind not in ['0','1','7','9','5','6','g','I'] { return false }
        line_end=start
        while line_end<length and @(page+line_end)!=10 { line_end++ }
        ; Skip the display label, then validate all three location fields.
        while start<line_end and @(page+start)!=9 { start++ }
        if start==line_end { return false }
        if not field(start+1,&next_selector,256) or field_end==line_end { return false }
        if not field(field_end+1,&next_endpoint,120) or field_end==line_end { return false }
        uword host_length=0
        while next_endpoint[lsb(host_length)]!=0 { host_length++ }
        if host_length==0 { return false }
        start=field_end+1
        uword port=0
        ubyte digits=0
        while start<line_end and @(page+start)!=9 {
            ubyte ch=@(page+start)
            if ch<'0' or ch>'9' or digits==5 { return false }
            if port>6553 or port==6553 and ch>'5' { return false }
            port=port*10+(ch-'0')
            next_endpoint[lsb(host_length+1+digits)]=ch
            digits++ start++
        }
        if port==0 or digits==0 { return false }
        next_endpoint[lsb(host_length)]=':'
        next_endpoint[lsb(host_length+1+digits)]=0
        return true
    }

    sub use_target() {
        void copy(&endpoint,&next_endpoint,128)
        void copy(&selector,&next_selector,256)
        kind=next_kind
    }

    sub download(str filename) -> bool {
        if not diskio.f_open_w(filename) { status=67 return false }
        if diskio.status_code()!=0 { diskio.f_close_w() status=67 return false }
        if not begin() { diskio.f_close_w() return false }
        uword used=0
        long total=0
        bool success=true
        while get() {
            if total==1048576 { status=68 success=false break }
            @(page+used)=status used++ total++
            if used==512 {
                if not diskio.f_write(page,used) { status=67 success=false break }
                used=0
            }
        }
        if status!=x16net.ERR_EOF { success=false }
        if success and used!=0 {
            if not diskio.f_write(page,used) { status=67 success=false }
        }
        close()
        diskio.f_close_w()
        return success
    }
}
