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
    ' use a hardcoded set of I2C pins not on the main bus as we have too many
    ' devices for the Propeller otherwise. To get the free pins back, a buffer
    ' could (and should) be installed on CLK, DIN and RST
    CLK_1   = (1<<26)
    CLK_0   = !(1<<26)
    DIN_1   = (1<<25)
    DIN_0   = !(1<<25)
    DOUT_1  = (1<<24)
    DOUT_0  = !(1<<24)

VAR
    LONG    CS_

PUB Init(Pin)
{{
Pin: pin assigned to flash CS
}}
    CS_ := (1 << Pin)
    OUTA |= CONSTANT(CLK_1 | DIN_1) | CS_
    DIRA |= CONSTANT(CLK_1 | DIN_1) | CS_
    
PUB Write(Record, Ptr, Length) | sector, p, n
{{
Write data from byte pointer Ptr of length Length to record number Record
Record  : 0-$3fff
Ptr     : byte pointer to data
Length  : 0-248
}}
    sector := Record >> 4
    Record := (Record & $0f) << 8
    
    if sector <> SectorNum
        ReadSector(sector)

    p := @BYTE[@SectorData][Record]
    n := $ffff_ffff
    repeat $40
        n &= LONG[p += 4]
        if n <> $ffff_ffff
            quit

    ByteMove(@BYTE[@SectorData][Record], @Header, 8)
    ByteMove(@BYTE[@SectorData][Record+8], Ptr, Length)
    if Length < $f8
        ByteFill(@BYTE[@SectorData][Record+8+Length], $ff, $f8 - Length)

    if n == $ffff_ffff
        WriteRecord(Record)
    else
        WriteSector

PUB Read(Record, Ptr, Length) | sector
{{
Read data into byte pointer Ptr of length Length from record number Record
Record  : 0-$3fff
Ptr     : byte ponter to data
Length  : 0-248

returns FALSE if no header found for the given record
}}
    sector := Record >> 4
    Record := (Record & $0f) << 8
    
    if sector <> SectorNum
        ReadSector(sector)

    if ValidRecord(Record)
        ByteMove(Ptr, @BYTE[@SectorData][Record+8], Length)
        result := TRUE
    else
        result := FALSE

PRI ValidRecord(Offset) | ptr
{{
Returns TRUE if the sector buffer contains a valid header at the given offset
}}
    ptr := @BYTE[@SectorData][Offset]
    return LONG[@Header][0] == LONG[ptr][0] and LONG[@Header][1] == LONG[ptr][1]

PRI ReadSector(Sector) | a
{{
Load the sector into the sector buffer
}}
    repeat while SR1 & $01
    a := Sector << 12

    OUTA &= !CS_
    SendByte($03)   ' read
    SendByte(BYTE[@a][2])
    SendByte(BYTE[@a][1])
    SendByte(BYTE[@a][0])

    a := 0
    repeat $1000
        BYTE[@SectorData][a++] := RecvByte

    OUTA |= CS_

    SectorNum := Sector

PRI WriteSector | a, o
{{
Write the sector back out to the device
}}
    repeat while SR1 & $01
    a := SectorNum << 12

    OUTA &= !CS_
    SendByte($06)   ' write enable
    OUTA |= CS_
    OUTA &= !CS_
    SendByte($20)   ' sector erase
    SendByte(BYTE[@a][2])
    SendByte(BYTE[@a][1])
    SendByte(BYTE[@a][0])
    OUTA |= CS_

    repeat o from 0 to $f00 step $100
        if ValidRecord(o)
            WriteRecord(o)    


PRI WriteRecord(Offset) | a
{{
Write just the record back to the device, having determined the existing data here is all $ff
}}
    repeat while SR1 & $01
    a := SectorNum << 12 + Offset

    OUTA &= !CS_
    SendByte($06)   ' write enable
    OUTA |= CS_
    OUTA &= !CS_
    SendByte($02)   ' page program
    SendByte(BYTE[@a][2])
    SendByte(BYTE[@a][1])
    SendByte(BYTE[@a][0])
    repeat $100
        SendByte(BYTE[@SectorData][Offset++])
    OUTA |= CS_

PRI SR1
{{
Returns the state of status register 1
}}
    OUTA &= !CS_
    SendByte($05)   ' read status register 1
    result := RecvByte
    OUTA |= CS_

PRI SendByte(b)
{{
Send 8 bit byte to device
}}
    repeat 8
        OUTA &= CLK_0
        if b & $80
            OUTA |= DIN_1
        else
            OUTA &= DIN_0
        OUTA |= CLK_1
        b <<= 1

PRI RecvByte 
{{
Receive 8 bit byte from device
}}
    result := 0
    repeat 8
        result <<= 1
        OUTA &= CLK_0
        if (INA & DOUT_1)
            result |= $01
        OUTA |= CLK_1
    return result

DAT
SectorNum   LONG    -1
SectorData  LONG    0[1024] ' 4K long aligned
Header      BYTE    "SFM60001"
