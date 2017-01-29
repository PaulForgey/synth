{
The MIT License (MIT)

Copyright (c) 2017 PaulForgey

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
}

CON
    BufSize         = 32        ' must have even log2
    BufMask         = BufSize-1

VAR
    LONG    Cog_
    LONG    Params_[8]
    LONG    Values_[3]
    LONG    Coarse_
    
PUB Start(BPin, MidiPin, DebugPin)
{{
ButtonPin:  : 0-25 base pin for buttons (9 pins)
MidiPin     : 0-31 pin for MIDI input
DebugPin    : 0-31 pin for RS232 output (115200 8-1-N)
}}
    Stop

    Params_[0] := BPin
    Params_[1] := @Buttons
    Params_[2] := MidiPin
    Params_[3] := DebugPin
    Params_[4] := @ChannelMask
    Params_[5] := @MidiBuffer
    Params_[6] := @MidiRecvPtr
    Params_[7] := @DebugOut

    ' start MIDI in omni mode for all the channels
    AddAllChannels

    ' set the output pins for the buttons' color
    DIRA |= (%000_111_000 << BPin)
    ButtonPin := BPin

    Cog_ := cognew(@entry, @Params_) + 1

PUB Stop
    if Cog_
        cogstop(Cog_ - 1)
    Cog_ := 0

PUB Pressed
{{
Return pressed button, 1-3 or 0 if none
State reset upon read
}}
    repeat result from 3 to 1
        if Buttons[result-1] & $8000_0000
            Buttons[result-1] &= $7fff_ffff
            quit

PUB Turned
{{
Return turned knob, 1-3 or 0 if none
State reset upon read
}}
    repeat result from 3 to 1
        if Values_[result-1] <> Knob(result)
            Values_[result-1] := Knob(result)
            quit

PUB SetColor(c) | mask
{{
Set color of the knobs, 0-7
}}
    mask := %111_000 << ButtonPin
    c <<= (ButtonPin + 3)
    OUTA := (OUTA & !mask) | (c ^ mask)

PUB Knob(b) | v
{{
Return value of knob, 1-3
}}
    v := (Buttons[b-1] & $ffff)
    return ~~v

PUB SetKnob(b, v)
{{
Set value of knob, 1-3
v       : signed 16 bit value
}}
    v &= $ffff
    LONG[@Buttons][b-1] := v
    Values_[b-1] := ~~v

PUB Value
{{
Return coarse+fine value of knobs 2 and 3 combined
}}
    return Knob(2) * Coarse_ + Knob(3)

PUB SetValue(v, c)
{{
Set coarse+fine value accross 2 knobs
v       : initial value, signed 16 bit
c       : level of movement for coarse adjustment
}}
    Coarse_ := c
    SetKnob(2, v / c)
    SetKnob(3, v // c)

PUB AddChannel(c)
{{
Add MIDI channel to receive messages for
}}
    ChannelMask := 1 << c

PUB RemoveChannel(c)
{{
Remove MIDI channel to receive messages for
}}
    ChannelMask &= !(1 << c)

PUB AddAllChannels
{{
Add all MIDI channels (omni mode)
}}
    ChannelMask := $ffff

PUB RemoveAllChannels
{{
Clear set of channels and receive no channel specific message at all
}}
    ChannelMask := 0

PUB RecvMidiControl
{{
receive MIDI control byte, or 0 if there either isn't one or would block
if a non-control byte is in the receive buffer, it is discarded
}}
    if MidiRecvPtr <> MidiReadPtr
        result := MidiBuffer[MidiReadPtr]
        MidiReadPtr := (MidiReadPtr+1) & BufMask
        
        if not (result & $80)
            result := 0
    else
        result := 0

PUB RecvMidiData(MsgPtr, Size) | n
{{
expect and receive Size bytes of midi data into byte array MsgPtr
if all Size control bytes canot be read without blocking, return FALSE and do not advance the read buffer
if a control byte is encountered before Size bytes, return all data bytes leaving the control byte in the read buffer

XXX this interface is kind of lame that it does not return the actual number read. This synth is designed to not depend
    on sysex messages to be variably sized in a way that would require this.
}}
    n := (MidiRecvPtr - MidiReadPtr) & BufMask
    if n < Size
        return FALSE
    
    repeat while Size--
        n := MidiBuffer[MidiReadPtr]
        if n & $80
            quit
        BYTE[MsgPtr++] := n
        MidiReadPtr := (MidiReadPtr+1) & BufMask
    
    return TRUE

PUB DebugChar(b)
{{
Send character b out the debug serial output
}}
    repeat while DebugOut
    DebugOut := b
    
PUB DebugStr(s) | b
{{
Send character string s out the debug serial output
}}
    repeat while b := BYTE[s++]
        DebugChar(b)

DAT
    org
entry
    mov ptr, PAR

    rdbyte button_pin, ptr              ' button base pin
    add ptr, #4
    
    mov button_mask, #%111_000_000
    shl button_mask, button_pin
    or DIRA, button_mask
    mov button_col, #%001_000_000
    shl button_col, button_pin
    
    rdword button_ptr, ptr
    add ptr, #4

    rdbyte r0, ptr
    add ptr, #4
    mov midi_pin, #1
    shl midi_pin, r0                    ' midi pin mask
    
    rdbyte r0, ptr
    add ptr, #4
    mov debug_pin, #1
    shl debug_pin, r0                   ' debug pin mask
    or DIRA, debug_pin

    rdword channel_ptr, ptr             ' midi channel
    add ptr, #4
    rdword midi_buf, ptr                ' midi buffer
    add ptr, #4
    rdword midi_ptr, ptr                ' midi buffer pointer
    add ptr, #4
    rdword debug_ptr, ptr               ' debug output

    mov midi_task, #midi
    mov debug_task, #debug
    
' button scanning task
button
    mov :scan, button_col               ' set rightmost button (0)
    mov :count, #3                      ' 3 buttons
    mov :ptr, button_ptr                ' reset value pointer

:loop
    andn OUTA, button_mask              ' light it up (which also selects it for reading)
    or OUTA, :scan
    mov button_wakeup, CNT
    add button_wakeup, button_clocks    ' poll for this long if no activity

:read
    mov :input, INA
    shr :input, button_pin
    and :input, #%111 wz                ' isolate the switches
    if_nz jmp #:value

    jmpret button_task, midi_task       ' wake up on button activity or polling interval

    mov t, button_wakeup
    sub t, CNT
    cmps t, #0 wc
    if_nc jmp #:read
    
:next
    andn OUTA, button_mask              ' let inputs settle
    shl :scan, #1                       ' light up next button
    add :ptr, #4                        ' move to next value
    djnz :count, #:loop
    jmp #button

:value                                  ' a button has done something
    test :input, #%100 wz               ' push?
    if_z jmp #:wait_rotate

:wait_push
    mov :input, INA
    shr :input, button_pin
    test :input, #%100 wz               ' wait for un-push

    if_z jmp #:push
    
    jmpret button_task, midi_task
    jmp #:wait_push

:push
    rdlong r0, :ptr                     ' set high bit of button value
    or r0, sign
    wrlong r0, :ptr
    jmp #:next
    
:wait_rotate
    mov r0, INA
    shr r0, button_pin
    test r0, #%011 wz, wc               ' wait for mid-click
    if_z jmp #:next                     ' went back to 0 before we were ready, skip it
    if_nc jmp #:wait_rotate0
    
    jmpret button_task, midi_task
    jmp #:wait_rotate

:wait_rotate0
    mov r0, INA
    shr r0, button_pin

    test r0, #%011 wz                   ' wait for 0 again
    if_z jmp #:rotate

    jmpret button_task, midi_task
    jmp #:wait_rotate0

:rotate
    rdlong r0, :ptr
    test r0, sign wc                    ' preserve push state
    test :input, #%001 wz               ' check for up or down
    if_z add r0, #1
    if_nz sub r0, #1
    muxc r0, sign                       ' restore push state
    wrlong r0, :ptr

    jmp #:next
    ' task local registers
:input      long    0
:ptr        long    0
:count      long    0
:scan       long    0

' midi reception task
midi
    test midi_pin, INA wz               ' start bit when input goes low
    if_z jmp #recv
    jmpret midi_task, debug_task
    jmp #midi
    
recv
    mov midi_wakeup, midi_start         ' wake up half period in to read in the middle of the bits
    add midi_wakeup, CNT
:start
    jmpret midi_task, debug_task

    mov t, midi_wakeup
    sub t, CNT
    cmps t, #0 wc
    if_nc jmp #:start
    
    add midi_wakeup, midi_clocks        ' wake up on next period

    mov :bits, #9                       ' clock in 9 bits
    mov :m, #0                          ' clear shift register
    
:bit
    jmpret midi_task, debug_task        ' wait for wakeup

    mov t, midi_wakeup
    sub t, CNT
    cmps t, #0 wc
    if_nc jmp #:bit

    add midi_wakeup, midi_clocks        ' wake up on next period

    test midi_pin, INA wc               ' data bit into C
    rcr :m, #1                          ' shift it in
    djnz :bits, #:bit                   ' do all 9

    if_nc jmp #midi                     ' stop bit should be a 1

    shr :m, #(32-9)                     ' move to lower 8

    and :m, #$ff
    test :m, #$80 wz                    ' control message?
    if_z jmp #:value

    cmp :m, #$f0 wc                     ' system common message?

    rdword :channel_mask, channel_ptr   ' update channel mask
    or :channel_mask, :all              ' provide a "not filtered" mask

    if_nc mov :channel, #$10            ' not filtered
    if_c mov :channel, :m
    if_c and :channel, #$0f             ' channel number of current control message
 
:value
    mov r0, #1
    shl r0, :channel
    test r0, :channel_mask wz
    if_z jmp #midi

    mov :mp, midi_buf
    add :mp, midi_pos
    wrbyte :m, :mp                      ' store to output

    add midi_pos, #1
    and midi_pos, #(BufSize-1)
    
    wrbyte midi_pos, midi_ptr           ' update waiter to where new data is

    jmp #midi
    ' task local registers
:m              long    0
:mp             long    0
:bits           long    0
:channel_mask   long    0
:channel        long    0
:all            long    $1_0000

' debug output task
debug
    rdbyte :d, debug_ptr wz             ' check for non-0 byte to write
    if_nz jmp #:out
    
    jmpret debug_task, button_task
    jmp #debug
    
:out
    or :d, #$100                        ' add stop bit (LSB shifted out first)
    wrbyte zero, debug_ptr              ' acknowledge output byte
    shl :d, #2
    or :d, #1                           ' add start bits
    mov :bits, #11
    mov debug_wakeup, CNT
    
:bit
    add debug_wakeup, debug_clocks
    ror :d, #1 wc                       ' shift out
    muxc OUTA, debug_pin
    
:wait
    jmpret debug_task, button_task
    mov t, debug_wakeup
    sub t, CNT
    cmps t, #0 wc
    if_nc jmp #:wait

    djnz :bits, #:bit                   ' next bit

    jmp #debug
    ' task local registers
:d      long    0
:bits   long    0

' constants    
button_clocks   long    200_000
midi_clocks     long    2560            ' 31250 baud
debug_clocks    long    694             ' 115200 baud
midi_start      long    2560 >> 1       ' half period into midi bit
sign            long    $8000_0000
midi_pos        long    0               ' position where to write next MIDI byte within buffer
zero            long    0

' general purpose registers not preserved between tasks
r0              res     1
ptr             res     1

' parameters
button_pin      res     1
button_mask     res     1
button_col      res     1
button_ptr      res     1
midi_pin        res     1
debug_pin       res     1
channel_ptr     res     1
midi_buf        res     1
midi_ptr        res     1
debug_ptr       res     1

' task switch data
button_wakeup   res     1
midi_wakeup     res     1
debug_wakeup    res     1
midi_task       res     1
button_task     res     1
debug_task      res     1
t               res     1

                fit

' the same facilities in the cog need to be available to multiple instances
' (there is no mutex protection, but only one thread at a time will using
'  any specific service)
Buttons         LONG    0[3]
ChannelMask     WORD    0
DebugOut        BYTE    0
MidiBuffer      BYTE    0[BufSize]
MidiRecvPtr     BYTE    0
MidiReadPtr     BYTE    0
ButtonPin       BYTE    0
