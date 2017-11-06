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
    BufSize         = 64        ' must have even log2
    BufMask         = BufSize-1

VAR
    LONG    Cog_
    LONG    Params_[10]
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
    Params_[7] := @SpiData
    Params_[8] := @SpiSize
    Params_[9] := @DebugOut

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

realtime messages are handled differently by being ignored.
If they are to ever be handled, it will be over a different mechanism invisible to this method.

returns length of data read. If < Size, an uncomsumed control byte was encountered
returns -1 if complete message has not yet been received
}}
    n := (MidiRecvPtr - MidiReadPtr) & BufMask
    if n < Size
        return -1

    result := 0
    repeat while Size--
        n := MidiBuffer[MidiReadPtr]
        if n & $80
            quit
        BYTE[MsgPtr++] := n
        MidiReadPtr := (MidiReadPtr+1) & BufMask
        result++

PUB RecvMidiBulk(MsgPtr, Size) | n
{{
receive, blocking if necessary, Size bytes of large midi data into byte array MsgPtr
This is callable after reading a header using RecvMidiData, e.g. determining a SYSEX message is relevant

returns length of data read. If < Size, an uncomsumed control byte was encountered
}}
    result := 0
    repeat while Size--
        repeat while MidiRecvPtr == MidiReadPtr
        n := MidiBuffer[MidiReadPtr]
        if n & $80
            return
        BYTE[MsgPtr++] := n
        MidiReadPtr := (MidiReadPtr+1) & BufMask
        result++

PUB SendSpi(pin, bits, out)
{{
Write to SPI bus

pin     : CS pin
bits    : size of data (up to 32)
out     : data to write
}}
    repeat while SpiSize
    SpiData := out >< bits
    SpiSize := (bits << 5) | pin

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
    
    rdword g_button, ptr
    add ptr, #4

    rdbyte r0, ptr
    add ptr, #4
    mov midi_pin, #1
    shl midi_pin, r0                    ' midi pin mask
    mov midi_pos, #0                    ' initialize midi task register
    
    rdbyte r0, ptr
    add ptr, #4
    mov debug_pin, #1
    shl debug_pin, r0                   ' debug pin mask
    or DIRA, debug_pin

    rdword g_channels, ptr              ' midi channels
    add ptr, #4
    rdword g_midi, ptr                  ' midi buffer
    add ptr, #4
    rdword g_midi_ptr, ptr              ' midi buffer pointer
    add ptr, #4
    rdword g_spi_data, ptr              ' spi output
    add ptr, #4
    rdword g_spi_size, ptr              ' spi pin/word size
    add ptr, #4
    rdword g_debug, ptr                 ' debug output

    mov midi_task, #midi
    mov spi_task, #spi
    mov debug_task, #debug

' button scanning task
button
    mov button_scan, button_col         ' set rightmost button (0)
    mov button_count, #3                ' 3 buttons
    mov button_ptr, g_button            ' reset value pointer

:loop
    andn OUTA, button_mask              ' light it up (which also selects it for reading)
    or OUTA, button_scan
    mov button_wakeup, CNT
    add button_wakeup, button_clocks    ' poll for this long if no activity

:read
    mov button_input, INA
    shr button_input, button_pin
    and button_input, #%111 wz          ' isolate the switches
    if_nz jmp #:value

    jmpret button_task, midi_task       ' wake up on button activity or polling interval

    mov t, button_wakeup
    sub t, CNT
    cmps t, #0 wc
    if_nc jmp #:read
    
:next
    andn OUTA, button_mask              ' let inputs settle
    shl button_scan, #1                 ' light up next button
    add button_ptr, #4                  ' move to next value
    djnz button_count, #:loop
    jmp #button

:value                                  ' a button has done something
    test button_input, #%100 wz         ' push?
    if_z jmp #:wait_rotate

:wait_push
    mov button_input, INA
    shr button_input, button_pin
    test button_input, #%100 wz         ' wait for un-push

    if_z jmp #:push
    
    jmpret button_task, midi_task
    jmp #:wait_push

:push
    rdlong r0, button_ptr               ' set high bit of button value
    or r0, sign
    wrlong r0, button_ptr
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
    rdlong r0, button_ptr
    test r0, sign wc                    ' preserve push state
    test button_input, #%001 wz         ' check for up or down
    if_z add r0, #1
    if_nz sub r0, #1
    muxc r0, sign                       ' restore push state
    wrlong r0, button_ptr

    jmp #:next

' midi reception task
midi
    test midi_pin, INA wz               ' start bit when input goes low
    if_z jmp #recv
    jmpret midi_task, spi_task
    jmp #midi
    
recv
    mov midi_wakeup, midi_start         ' wake up half period in to read in the middle of the bits
    add midi_wakeup, CNT
:start
    jmpret midi_task, spi_task

    mov t, midi_wakeup
    sub t, CNT
    cmps t, #0 wc
    if_nc jmp #:start
    
    add midi_wakeup, midi_clocks        ' wake up on next period

    mov midi_bits, #9                   ' clock in 9 bits
    mov midi_m, #0                      ' clear shift register
    
:bit
    jmpret midi_task, spi_task          ' wait for wakeup

    mov t, midi_wakeup
    sub t, CNT
    cmps t, #0 wc
    if_nc jmp #:bit

    add midi_wakeup, midi_clocks        ' wake up on next period

    test midi_pin, INA wc               ' data bit into C
    rcr midi_m, #1                      ' shift it in
    djnz midi_bits, #:bit               ' do all 9

    if_nc jmp #midi                     ' stop bit should be a 1

    shr midi_m, #(32-9)                 ' move to lower 8

    and midi_m, #$ff
    test midi_m, #$80 wz                ' control message?
    if_z jmp #:value

    cmp midi_m, #$f0 wc                 ' system common message?
    if_nc test midi_m, #$08 wz          ' if system common, realtime?
    if_nc_and_nz jmp #midi              ' toss realtime

    rdword midi_mask, g_channels        ' update channel mask
    or midi_mask, midi_all              ' provide a "not filtered" mask

    if_nc mov midi_channel, #$10        ' not filtered
    if_c mov midi_channel, midi_m
    if_c and midi_channel, #$0f         ' channel number of current control message
 
:value
    mov r0, #1
    shl r0, midi_channel
    test r0, midi_mask wz
    if_z jmp #midi

    mov midi_mp, g_midi
    add midi_mp, midi_pos
    wrbyte midi_m, midi_mp              ' store to output

    add midi_pos, #1
    and midi_pos, #BufMask
    
    wrbyte midi_pos, g_midi_ptr          ' update waiter to where new data is

    jmp #midi

' spi output task
spi
    or OUTA, #%101_1011                 ' bit 3 is the address line, selectable externally
    or DIRA, #%101_1011                 ' set all SPI pins as outputs and high (except address line and flash CS)

    andn OUTA, #%100_0000               ' reset
    mov spi_wakeup, CNT
    add spi_wakeup, button_clocks
:reset
    jmpret spi_task, debug_task
    mov t, spi_wakeup
    sub t, CNT
    cmps t, #0 wc
    if_nc jmp #:reset
    or OUTA, #%100_0000

:wait
    rdword spi_size, g_spi_size wz      ' output waiting?
    if_nz jmp #:send
    jmpret spi_task, debug_task
    jmp #:wait

:send
    rdlong spi_out, g_spi_data          ' pre bit reversed
    mov spi_cs, #1
    shl spi_cs, spi_size                ' select CS pin
    wrword zero, g_spi_size             ' acknowledge we got it
    shr spi_size, #5                    ' how many bits

    andn OUTA, spi_cs                   ' CS lo
:bit
    andn OUTA, #%10                     ' CLK lo
    jmpret spi_task, debug_task
    shr spi_out, #1 wc
    muxc OUTA, #1                       ' data bit to DIN
    jmpret spi_task, debug_task
    or OUTA, #%10                       ' CLK hi
    jmpret spi_task, debug_task
    djnz spi_size, #:bit

    or OUTA, spi_cs                     ' CS hi
    jmp #:wait

' debug output task
debug
    rdbyte debug_d, g_debug wz          ' check for non-0 byte to write
    if_nz jmp #:out
    
    jmpret debug_task, button_task
    jmp #debug
    
:out
    or debug_d, #$100                   ' add stop bit (LSB shifted out first)
    wrbyte zero, g_debug                ' acknowledge output byte
    shl debug_d, #2
    or debug_d, #1                      ' add start bits
    mov debug_bits, #11
    mov debug_wakeup, CNT
    
:bit
    add debug_wakeup, debug_clocks
    ror debug_d, #1 wc                  ' shift out
    muxc OUTA, debug_pin
    
:wait
    jmpret debug_task, button_task
    mov t, debug_wakeup
    sub t, CNT
    cmps t, #0 wc
    if_nc jmp #:wait

    djnz debug_bits, #:bit              ' next bit

    jmp #debug

' constants    
button_clocks   long    200_000
midi_clocks     long    2560            ' 31250 baud
debug_clocks    long    694             ' 115200 baud
midi_start      long    2560 >> 1       ' half period into midi bit
sign            long    $8000_0000      ' high bit
midi_all        long    $1_0000         ' pseudo channel bypassing filter
zero            long    0

' general purpose registers not preserved between tasks
r0              res     1
ptr             res     1

' button task
button_scan     res     1
button_count    res     1
button_ptr      res     1
button_input    res     1

' midi task
midi_bits       res     1
midi_pos        res     1
midi_m          res     1
midi_mp         res     1
midi_mask       res     1
midi_channel    res     1

' spi task
spi_bits        res     1
spi_size        res     1
spi_out         res     1
spi_cs          res     1

' debug task
debug_d         res     1
debug_bits      res     1

' parameters
button_pin      res     1
button_mask     res     1
button_col      res     1
g_button        res     1
midi_pin        res     1
debug_pin       res     1
g_channels      res     1
g_midi          res     1
g_midi_ptr      res     1
g_spi_data      res     1
g_spi_size      res     1
g_debug         res     1

' task switch data
button_wakeup   res     1
midi_wakeup     res     1
spi_wakeup      res     1
debug_wakeup    res     1
midi_task       res     1
button_task     res     1
spi_task        res     1
debug_task      res     1
t               res     1

                fit

' the same facilities in the cog need to be available to multiple instances
' (there is no mutex protection, but only one thread at a time will using
'  any specific service)
Buttons         LONG    0[3]
SpiData         LONG    0
SpiSize         WORD    0
ChannelMask     WORD    0
DebugOut        BYTE    0
MidiBuffer      BYTE    0[BufSize]
MidiRecvPtr     BYTE    0
MidiReadPtr     BYTE    0
ButtonPin       BYTE    0
