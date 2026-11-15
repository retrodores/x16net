; x16net: standalone 65C02 UART/Zimodem library. MIT license.
; No zero page, KERNAL calls, IRQ hooks, or display access.
.cpu "65c02"
.enc "ascii"
.cdef 0,127,0
BASE = $8000
* = BASE
jmp init
jmp shutdown
jmp get_byte
jmp put_byte
jmp read_block
jmp write_block
jmp status
jmp set_timeout
jmp prepare
jmp connect
jmp disconnect
jmp abi_info
; ABI header at +36. Stable across compatible releases.
.text "X16N"
.byte 1, 0, 12, 0     ; major, minor, entries, reserved
.word library_end-BASE

OK=0
AGAIN=1
TIMEOUT=2
BADARG=3
NOCARD=4
STATE=5
EOF=6
IOERR=7
MODEM=8
OVERFLOW=9
SERIAL=1
READY=2
CONNECTED=3
FAULT=4

; A=baud index 0..7, XY=UART address. Destructive initialization.
init:
    cld
    pha
    tya
    cmp #$9f
    bne init_invalid
    txa
    and #7
    bne init_invalid
    cpx #$60
    bcc init_invalid
    cpx #$b0
    beq init_invalid
    cpx #$b8
    beq init_invalid
    pla
    cmp #8
    bcs badarg
    sta baud
    stz state
    stx uart_read+1
    sty uart_read+2
    ; Scratch-register probe, restored even on failure. Explicit port only.
    ldx #7
    jsr uart_read
    pha
    lda #$55
    jsr uart_write
    jsr uart_read
    cmp #$55
    bne probe_bad
    lda #$aa
    jsr uart_write
    jsr uart_read
    cmp #$aa
    bne probe_bad
    pla
    jsr uart_write
    ; DLAB, divisor, 8N1, disabled UART IRQs, clear/enable 16-byte FIFOs.
    ldx #3
    lda #$80
    jsr uart_write
    ldx baud
    lda divisors,x
    ldx #0
    jsr uart_write
    ldx #1
    lda #0
    jsr uart_write
    ldx #3
    lda #3
    jsr uart_write
    ldx #1
    lda #0
    jsr uart_write
    ldx #2
    lda #$87
    jsr uart_write
    ; AFE + OPA inactive/high + RTS + DTR. Same MCR value as ROMTERM.
    ldx #4
    lda #$27
    jsr uart_write
    lda #SERIAL
    sta state
    lda #$20
    sta timeout+2
    stz timeout
    stz timeout+1
    jmp success
init_invalid:
    pla
badarg:
    lda #BADARG
    sec
    rts
probe_bad:
    pla
    jsr uart_write
    lda #NOCARD
    sec
    rts

shutdown:
    cld
    lda state
    beq success
    ldx #1
    lda #0
    jsr uart_write
    ; OPA stays inactive. DTR/RTS deasserted.
    ldx #4
    lda #4
    jsr uart_write
    stz state
success:
    lda #OK
    clc
    rts
state_error:
    lda #STATE
    sec
    rts
again:
    lda #AGAIN
    sec
    rts
io_error:
    lda #IOERR
    sec
    rts

get_byte:
    cld
    lda state
    beq state_error
    cmp #FAULT
    beq state_error
    ldx #5
    jsr uart_read
    sta last_lsr
    and #$1e
    bne io_error
    lda last_lsr
    and #1
    bne rx_available
    lda state
    cmp #CONNECTED
    bne again
    ldx #6
    jsr uart_read
    and #$80
    bne again
    ; FIFO drained before EOF. Quiet mode guarantees no modem text trailer.
    lda #EOF
    sec
    rts
rx_available:
    ldx #0
    jsr uart_read
    clc
    rts

put_byte:
    cld
    sta tx_byte
    lda state
    beq state_error
    cmp #FAULT
    beq state_error
    cmp #CONNECTED
    bne tx_status
    ldx #6
    jsr uart_read
    and #$80
    bne tx_status
    lda #EOF
    sec
    rts
tx_status:
    ldx #5
    jsr uart_read
    and #$20
    beq again
    ldx #0
    lda tx_byte
    jsr uart_write
    jmp success

; Nonblocking caller-buffer transfers. A=1..255, 0=256. XY=buffer.
; Return XY=transferred, A=result, carry=result!=0. No implicit retries.
read_block:
    cld
    jsr buffer_setup
    bcs block_bad
read_loop:
    jsr get_byte
    bcs block_done
buffer_store:
    sta $ffff
    jsr advance_buffer
    bne read_loop
    jmp success_block

write_block:
    cld
    jsr buffer_setup
    bcs block_bad
write_loop:
buffer_load:
    lda $ffff
    jsr put_byte
    bcs block_done
    jsr advance_buffer
    bne write_loop
success_block:
    lda #OK
block_done:
    pha
    ldx count
    ldy count+1
    pla
    cmp #1
    rts
block_bad:
    ldx #0
    ldy #0
    sec
    rts

buffer_setup:
    sta remaining
    stz remaining+1
    stz count
    stz count+1
    cmp #0
    bne length_set
    inc remaining+1
length_set:
    ; Restrict caller buffers to $0200..$7fff, including entire extent.
    cpy #2
    bcc buffer_invalid
    cpy #$80
    bcs buffer_invalid
    stx buffer_load+1
    sty buffer_load+2
    stx buffer_store+1
    sty buffer_store+2
    txa
    clc
    adc remaining
    sta scratch
    tya
    adc remaining+1
    cmp #$80
    bcc buffer_valid
    bne buffer_invalid
    lda scratch          ; end-exclusive $8000 is allowed
    bne buffer_invalid
buffer_valid:
    clc
    rts
buffer_invalid:
    jmp badarg
advance_buffer:
    inc buffer_load+1
    bne pointer_advanced
    inc buffer_load+2
pointer_advanced:
    inc buffer_store+1
    bne store_advanced
    inc buffer_store+2
store_advanced:
    inc count
    bne count_advanced
    inc count+1
count_advanced:
    lda remaining
    bne remaining_low
    dec remaining+1
remaining_low:
    dec remaining
    lda remaining
    ora remaining+1
    rts

status:
    lda state
    beq state_error
    ldx #5
    jsr uart_read
    pha
    ldx #6
    jsr uart_read
    tay
    pla
    tax
    lda state
    clc
    rts
set_timeout:
    cld
    sta timeout_high
    stx timeout_low
    sty timeout_low+1
    ora timeout_low
    ora timeout_low+1
    beq bad_timeout
    lda timeout_high
    sta timeout+2
    stx timeout
    sty timeout+1
    jmp success
bad_timeout:
    jmp badarg

; prepare requires an already idle modem command interpreter. Does not save
; settings or provision Wi-Fi. Q0 restores responses; R0 selects CR-only.
prepare:
    cld
    lda state
    cmp #SERIAL
    beq prepare_start
    cmp #READY
    bne prepare_state
prepare_start:
    jsr start_budget
    lda #<prepare_command
    sta command_load+1
    lda #>prepare_command
    sta command_load+2
    jsr send_command
    bcs operation_fault
    jsr wait_result
    bcs operation_fault
    cmp #1
    bne modem_fault
    lda #READY
    sta state
    jmp success
prepare_state:
    jmp state_error
modem_fault:
    lda #MODEM
operation_fault:
    pha
    lda #FAULT
    sta state
    pla
    sec
    rts

; Quiet streaming is intentional: modem responses must never become payload.
; XY -> NUL terminated ASCII DNS-name/IPv4:port, maximum 95 bytes.
connect:
    cld
    lda state
    cmp #READY
    bne connect_state
    cpy #2
    bcc connect_badarg
    cpy #$80
    bcs connect_badarg
    stx endpoint_load+1
    sty endpoint_load+2
    stz endpoint_length
    stz colon_seen
validate_endpoint:
    lda endpoint_load+2
    cmp #$80
    bcs connect_badarg
endpoint_load:
    lda $ffff
    beq endpoint_complete
    ldx endpoint_length
    cpx #95
    bcs connect_badarg
    cmp #':'
    bne endpoint_char
    cpx #0
    beq connect_badarg
    inc colon_seen
endpoint_char:
    ; Deliberately reject quotes, CR/LF and AT-command injection.
    cmp #'-'
    beq endpoint_accept
    cmp #'.'
    beq endpoint_accept
    cmp #':'
    beq endpoint_accept
    cmp #'0'
    bcc connect_badarg
    cmp #'9'+1
    bcc endpoint_accept
    cmp #'A'
    bcc connect_badarg
    cmp #'Z'+1
    bcc endpoint_accept
    cmp #'a'
    bcc connect_badarg
    cmp #'z'+1
    bcs connect_badarg
endpoint_accept:
    sta dial_command+6,x
    inc endpoint_length
    inc endpoint_load+1
    bne validate_endpoint
    inc endpoint_load+2
    jmp validate_endpoint
endpoint_complete:
    ldx endpoint_length
    beq connect_badarg
    lda colon_seen
    cmp #1
    bne connect_badarg
    lda dial_command+5,x
    cmp #':'
    beq connect_badarg
    lda #'"'
    sta dial_command+6,x
    lda #13
    sta dial_command+7,x
    lda #0
    sta dial_command+8,x
    jsr start_budget
    lda #<dial_command
    sta command_load+1
    lda #>dial_command
    sta command_load+2
    jsr send_command
    bcs connect_fault
wait_carrier:
    jsr tick_budget
    bcs connect_fault
    ldx #6
    jsr uart_read
    and #$80
    beq wait_carrier
    lda #CONNECTED
    sta state
    jmp success
connect_state:
    jmp state_error
connect_badarg:
    jmp badarg
connect_fault:
    jmp operation_fault

; Explicit disconnect discards unread data. Keep DTR down until DCD drops.
; A timed-out dial remains FAULT: cannot prove a pending dial has finished.
disconnect:
    cld
    lda state
    cmp #READY
    beq disconnect_ok
    cmp #CONNECTED
    bne disconnect_state
    jsr start_budget
    ldx #4
    lda #$26
    jsr uart_write
disconnect_wait:
    jsr tick_budget
    bcs disconnect_fault
    ldx #6
    jsr uart_read
    and #$80
    bne disconnect_wait
    ldx #2
    lda #$87
    jsr uart_write
    ldx #4
    lda #$27
    jsr uart_write
    lda #READY
    sta state
disconnect_ok:
    jmp success
disconnect_state:
    jmp state_error
disconnect_fault:
    ; Leave DTR deasserted on failure.
    jmp operation_fault

abi_info:
    lda #1
    ldx #<BASE
    ldy #>BASE
    clc
    rts

; Low-level hardware functions use self-modifying absolute addressing.
; They may run only from writable unbanked RAM.
uart_read:
    lda $9fe0,x
    rts
uart_write:
    ; No indexed hardware stores: avoid dummy reads of RX data on UART writes.
    pha
    txa
    clc
    adc uart_read+1
    sta uart_store+1
    lda uart_read+2
    sta uart_store+2
    pla
uart_store:
    sta $9fe0
    rts

start_budget:
    lda timeout
    sta budget
    lda timeout+1
    sta budget+1
    lda timeout+2
    sta budget+2
    rts
tick_budget:
    lda budget
    ora budget+1
    ora budget+2
    beq expired
    lda budget
    bne budget_low
    lda budget+1
    bne budget_mid
    dec budget+2
budget_mid:
    dec budget+1
budget_low:
    dec budget
    clc
    rts
expired:
    lda #TIMEOUT
    sec
    rts

send_command:
    jsr tick_budget
    bcs send_done
command_load:
    lda $ffff
    beq send_success
    jsr put_byte
    bcc command_next
    cmp #AGAIN
    beq send_command
    sec
    rts
command_next:
    inc command_load+1
    bne send_command
    inc command_load+2
    jmp send_command
send_success:
    clc
send_done:
    rts

; Bounded exact-line result parser, used only in command mode.
; A=1 for OK, 2 for ERROR; unrelated lines/echo are ignored.
wait_result:
    stz line_length
result_loop:
    jsr tick_budget
    bcs result_done
    jsr get_byte
    bcc result_char
    cmp #AGAIN
    beq result_loop
    sec
    rts
result_char:
    cmp #13
    beq result_line
    cmp #10
    beq result_loop
    ldx line_length
    cpx #63
    bcs result_overflow
    sta line_buffer,x
    inc line_length
    jmp result_loop
result_line:
    ldx line_length
    beq result_loop
    cpx #2
    bne check_error
    lda line_buffer
    cmp #'O'
    bne result_other
    lda line_buffer+1
    cmp #'K'
    bne result_other
    lda #1
    clc
    rts
check_error:
    cpx #5
    bne result_other
    ldx #4
error_compare:
    lda line_buffer,x
    cmp error_text,x
    bne result_other
    dex
    bpl error_compare
    lda #2
    clc
    rts
result_other:
    stz line_length
    jmp result_loop
result_overflow:
    lda #OVERFLOW
    sec
result_done:
    rts

divisors: .byte 96,48,24,16,8,4,2,1
prepare_command:
    .text "ATE0V1Q0X0F0R0&P0S62=0S63=2S46=0S48=0S50=0S54=0N0H"
    .byte 13,0
error_text: .text "ERROR"
dial_command: .text "ATQ1D"
    .byte '"'
    .fill 98,0
state: .byte 0
baud: .byte 0
tx_byte: .byte 0
last_lsr: .byte 0
scratch: .byte 0
timeout_high: .byte 0
timeout_low: .word 0
timeout: .byte 0,0,$20
budget: .fill 3,0
remaining: .word 0
count: .word 0
endpoint_length: .byte 0
colon_seen: .byte 0
line_length: .byte 0
line_buffer: .fill 64,0
library_end:
.cerror library_end > $9f00, "library overlaps I/O"
