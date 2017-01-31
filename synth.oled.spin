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

OBJ
    io      : "synth.io"

VAR
    BYTE    Pin_

PUB Init(Pin) | x
{{
Init OLED display
Pin     : Pin assigned to SPI CS line
}}
    Pin_ := Pin
    DIRA |= %100 ' address line

    Send(0, $af)
    repeat x from $b0 to $b3
        Send(0, x)
        Send(0, $00)
        Send(0, $10)
        repeat 132
            Send(1, 0)

PRI PutC(c) | ptr, inverse
{{
Paint a character at the display's current memory location
}}
        if c => 32  ' ASCII characters, which use 5 columns plus 1 blank
            if c & $80
                c &= $7f
                inverse := $ff
            else
                inverse := 0
            ptr := @BYTE[@Chars][(c-32) * 5]
            repeat 5
                Send(1, BYTE[ptr++] ^ inverse)
            Send(1, 0)
        else        ' Graphics characters, which also use all 6 columns
            ptr := @BYTE[@Graphics][(c-1) * 6]
            repeat 6
                Send(1, BYTE[ptr++])

PRI Point(row, col)
{{
Set the display's current memory location to the given row and column.
row     : 0-3, with 0 on top
col     : 0-42, 0 at left. Each column is 3 pixels, or 1/2 the width of a character cell
}}
    Send(0, $b0+row)
    Send(0, col & $f)
    Send(0, (col >> 4) | $10)

PUB Put(row, col, c)
{{
Put a character at a given row and column
row     : 0-3, with 0 on top
col     : 0-42, 0 at left. Each column is 3 pixels, or 1/2 the width of a character cell
}}
    Point(row, col*3)
    PutC(c)

PUB Write(row, col, str) | c, ptr, inverse
{{
Write a character string to a given row and column
row     : 0-3, with 0 on top
col     : 0-42, 0 at left. Each column is 3 pixels, or 1/2 the width of a character cell
}}
    Point(row, col*3)
    repeat while c := BYTE[str++]
        PutC(c)

PUB Clear(x1, y1, x2, y2) | y, x
{{
Clear top left x1,y1 to bottom right x2,y2
}}
    repeat y from y1 to y2
        Point(y, x1)
        repeat x from x1 to x2
            Send(1, 0)

PRI Send(a, d) | cs
{{
Send SPI byte to display device
a       : 0 for command, 1 for data
d       : 8 bit data
}}
    if a
        OUTA |= %100
    else
        OUTA &= CONSTANT(!%100)

    io.SendSpi(Pin_, 8, d)

DAT
' 6 bytes per tile
Graphics

' 1
' ....**
' ..**..
' .*....
' *.....
' ......
' ......
' ......
' ......
BYTE    %00001000
BYTE    %00000100
BYTE    %00000010
BYTE    %00000010
BYTE    %00000001
BYTE    %00000001

' 2
' **....
' ..**..
' ....*.
' .....*
' ......
' ......
' ......
' ......
BYTE    %00000001
BYTE    %00000001
BYTE    %00000010
BYTE    %00000010
BYTE    %00000100
BYTE    %00001000

' 3
' ......
' ......
' ......
' ......
' *.....
' .*....
' ..**..
' ....**
BYTE    %00010000
BYTE    %00100000
BYTE    %01000000
BYTE    %01000000
BYTE    %10000000
BYTE    %10000000

' 4
' ......
' ......
' ......
' ......
' .....*
' ....*.
' ..**..
' **....
BYTE    %10000000
BYTE    %10000000
BYTE    %01000000
BYTE    %01000000
BYTE    %00100000
BYTE    %00010000

' 5
' ......
' ....**
' ..**..
' **....
' ......
' ......
' ......
' ......
BYTE    %00001000
BYTE    %00001000
BYTE    %00000100
BYTE    %00000100
BYTE    %00000010
BYTE    %00000010

' 6
' **....
' ..**..
' ....**
' ......
' ......
' ......
' ......
' ......
BYTE    %00000001
BYTE    %00000001
BYTE    %00000010
BYTE    %00000010
BYTE    %00000100
BYTE    %00000100

' 7
' ......
' ......
' ......
' **....
' ..**..
' ....**
' ......
' ......
BYTE    %00001000
BYTE    %00001000
BYTE    %00010000
BYTE    %00010000
BYTE    %00100000
BYTE    %00100000

' 8
' ......
' ......
' ......
' ......
' ....**
' ..**..
' **....
' ......
BYTE    %01000000
BYTE    %01000000
BYTE    %00100000
BYTE    %00100000
BYTE    %00010000
BYTE    %00010000

' 9
' *.....
' *.....
' *.....
' *.....
' *...**
' *.**..
' **....
' *.....
BYTE    %11111111
BYTE    %01000000
BYTE    %00100000
BYTE    %00100000
BYTE    %00010000
BYTE    %00010000

' 10
' **....
' *.**..
' *...**
' *.....
' *.....
' *.....
' *.....
' *.....
BYTE    %11111111
BYTE    %00000001
BYTE    %00000010
BYTE    %00000010
BYTE    %00000100
BYTE    %00000100

' 11
' ******
' *.....
' *.....
' *.....
' *.....
' *.....
' *.....
' *.....
BYTE    %11111111
BYTE    %00000001
BYTE    %00000001
BYTE    %00000001
BYTE    %00000001
BYTE    %00000001

' 12
' ******
' ......
' ......
' ......
' ......
' ......
' ......
' ......
BYTE    %00000001
BYTE    %00000001
BYTE    %00000001
BYTE    %00000001
BYTE    %00000001
BYTE    %00000001

' 13
' *.....
' *.....
' *.....
' *.....
' *.....
' *.....
' *.....
' ******
BYTE    %11111111
BYTE    %10000000
BYTE    %10000000
BYTE    %10000000
BYTE    %10000000
BYTE    %10000000

' 14
' ......
' ......
' ......
' ......
' ......
' ......
' ......
' ******
BYTE    %10000000
BYTE    %10000000
BYTE    %10000000
BYTE    %10000000
BYTE    %10000000
BYTE    %10000000
 
' 5x7 tiles, left to right, LSB on top
' 5 bytes per tile (0 written after each char sequence for non drawing tiles)
Chars
' (space)
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0000000
' !
' ..*..
' ..*..
' ..*..
' ..*..
' ..*..
' .....
' ..*..
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_1011111
BYTE	%0_0000000
BYTE	%0_0000000
' "
' .*.*.
' .*.*.
' .....
' .....
' .....
' .....
' .....
BYTE	%0_0000000
BYTE	%0_0000011
BYTE	%0_0000000
BYTE	%0_0000011
BYTE	%0_0000000
' #
' .*.*.
' *****
' .*.*.
' *****
' .*.*.
' .....
' .....
BYTE	%0_0001010
BYTE	%0_0011111
BYTE	%0_0001010
BYTE	%0_0011111
BYTE	%0_0001010
' $
' ..*..
' .****
' *.*..
' .***.
' ..*.*
' ****.
' ..*..
BYTE	%0_0100100
BYTE	%0_0101010
BYTE	%0_1111111
BYTE	%0_0101010
BYTE	%0_0010010
' %
' .....
' *...*
' ...*.
' ..*..
' .*...
' *...*
' .....
BYTE	%0_0100010
BYTE	%0_0010000
BYTE	%0_0001000
BYTE	%0_0000100
BYTE	%0_0100010
' &
' .*...
' *.*..
' *.*..
' .*...
' *.*.*
' *..*.
' .**.*
BYTE	%0_0110110
BYTE	%0_1001001
BYTE	%0_1010110
BYTE	%0_0100000
BYTE	%0_1010000
' _'
' ..*..
' ..*..
' .....
' .....
' .....
' .....
' .....
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0000011
BYTE	%0_0000000
BYTE	%0_0000000
' (
' ....*
' ...*.
' ...*.
' ...*.
' ...*.
' ...*.
' ....*
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0111110
BYTE	%0_1000001
' )
' *....
' .*...
' .*...
' .*...
' .*...
' .*...
' *....
BYTE	%0_1000001
BYTE	%0_0111110
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0000000
' *
' .....
' *.*.*
' .***.
' *****
' .***.
' *.*.*
' .....
BYTE	%0_0101010
BYTE	%0_0011100
BYTE	%0_0111110
BYTE	%0_0011100
BYTE	%0_0101010
' +
' .....
' ..*..
' ..*..
' *****
' ..*..
' ..*..
' .....
BYTE	%0_0001000
BYTE	%0_0001000
BYTE	%0_0111110
BYTE	%0_0001000
BYTE	%0_0001000
' ,
' .....
' .....
' .....
' .....
' .....
' ..*..
' .*...
BYTE	%0_0000000
BYTE	%0_1000000
BYTE	%0_0100000
BYTE	%0_0000000
BYTE	%0_0000000
' -
' .....
' .....
' .....
' *****
' .....
' .....
' .....
BYTE	%0_0001000
BYTE	%0_0001000
BYTE	%0_0001000
BYTE	%0_0001000
BYTE	%0_0001000
' .
' .....
' .....
' .....
' .....
' .....
' .....
' ..*..
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_1000000
BYTE	%0_0000000
BYTE	%0_0000000
' /
' .....
' ....*
' ...*.
' ..*..
' .*...
' *....
' .....
BYTE	%0_0100000
BYTE	%0_0010000
BYTE	%0_0001000
BYTE	%0_0000100
BYTE	%0_0000010
' 0
' .***.
' *...*
' *..**
' *.*.*
' **..*
' *...*
' .***.
BYTE	%0_0111110
BYTE	%0_1010001
BYTE	%0_1001001
BYTE	%0_1000101
BYTE	%0_0111110
' 1
' ..*..
' .**..
' ..*..
' ..*..
' ..*..
' ..*..
' .***.
BYTE	%0_0000000
BYTE	%0_1000010
BYTE	%0_1111111
BYTE	%0_1000000
BYTE	%0_0000000
' 2
' .***.
' *...*
' ....*
' .***.
' *....
' *....
' *****
BYTE	%0_1110010
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1000110
' 3
' .***.
' *...*
' ....*
' .***.
' ....*
' *...*
' .***.
BYTE	%0_0100010
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_0110110
' 4
' *...*
' *...*
' *...*
' *****
' ....*
' ....*
' ....*
BYTE	%0_0001111
BYTE	%0_0001000
BYTE	%0_0001000
BYTE	%0_0001000
BYTE	%0_1111111
' 5
' *****
' *....
' *....
' .***.
' ....*
' *...*
' .***.
BYTE	%0_0100111
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_0110001
' 6
' .***.
' *...*
' *....
' ****.
' *...*
' *...*
' .***.
BYTE	%0_0111110
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_0110010
' 7
' *****
' ....*
' ....*
' ...*.
' ..*..
' .*...
' *....
BYTE	%0_1000001
BYTE	%0_0100001
BYTE	%0_0010001
BYTE	%0_0001001
BYTE	%0_0000111
' 8
' .***.
' *...*
' *...*
' .***.
' *...*
' *...*
' .***.
BYTE	%0_0110110
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_0110110
' 9
' .***.
' *...*
' *...*
' .****
' ....*
' *...*
' .***.
BYTE	%0_0100110
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_0111110
' :
' .....
' ..*..
' .....
' .....
' .....
' ..*..
' .....
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0100010
BYTE	%0_0000000
BYTE	%0_0000000
' ;
' .....
' ..*..
' .....
' .....
' .....
' ..*..
' .*...
BYTE	%0_0000000
BYTE	%0_1000000
BYTE	%0_0100010
BYTE	%0_0000000
BYTE	%0_0000000
' <
' .....
' ...*.
' ..*..
' .*...
' ..*..
' ...*.
' .....
BYTE	%0_0000000
BYTE	%0_0001000
BYTE	%0_0010100
BYTE	%0_0100010
BYTE	%0_0000000
' =
' .....
' .....
' *****
' .....
' *****
' .....
' .....
BYTE	%0_0010100
BYTE	%0_0010100
BYTE	%0_0010100
BYTE	%0_0010100
BYTE	%0_0010100
' >
' .....
' .*...
' ..*..
' ...*.
' ..*..
' .*...
' .....
BYTE	%0_0000000
BYTE	%0_0100010
BYTE	%0_0010100
BYTE	%0_0001000
BYTE	%0_0000000
' ?
' .***.
' *...*
' ....*
' ..**.
' ..*..
' .....
' ..*..
BYTE	%0_0000010
BYTE	%0_0000001
BYTE	%0_1011001
BYTE	%0_0001001
BYTE	%0_0000110
' _@
' .***.
' *...*
' *.*.*
' *.***
' *....
' *....
' .***.
BYTE	%0_0111110
BYTE	%0_1000001
BYTE	%0_1001101
BYTE	%0_1001001
BYTE	%0_0001110
' A
' .***.
' *...*
' *...*
' *****
' *...*
' *...*
' *...*
BYTE	%0_1111110
BYTE	%0_0001001
BYTE	%0_0001001
BYTE	%0_0001001
BYTE	%0_1111110
' B
' ****.
' *...*
' *...*
' ****.
' *...*
' *...*
' ****.
BYTE	%0_1111111
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_0110110
' C
' .****
' *....
' *....
' *....
' *....
' *....
' .****
BYTE	%0_0111110
BYTE	%0_1000001
BYTE	%0_1000001
BYTE	%0_1000001
BYTE	%0_1000001
' D
' ****.
' *...*
' *...*
' *...*
' *...*
' *...*
' ****.
BYTE	%0_1111111
BYTE	%0_1000001
BYTE	%0_1000001
BYTE	%0_1000001
BYTE	%0_0111110
' E
' *****
' *....
' *....
' ****.
' *....
' *....
' *****
BYTE	%0_1111111
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1000001
' F
' *****
' *....
' *....
' ****.
' *....
' *....
' *....
BYTE	%0_1111111
BYTE	%0_0001001
BYTE	%0_0001001
BYTE	%0_0001001
BYTE	%0_0000001
' G
' .****
' *....
' *....
' *.***
' *...*
' *...*
' .****
BYTE	%0_0111110
BYTE	%0_1000001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1111001
' H
' *...*
' *...*
' *...*
' *****
' *...*
' *...*
' *...*
BYTE	%0_1111111
BYTE	%0_0001000
BYTE	%0_0001000
BYTE	%0_0001000
BYTE	%0_1111111
' I
' .***.
' ..*..
' ..*..
' ..*..
' ..*..
' ..*..
' .***.
BYTE	%0_0000000
BYTE	%0_1000001
BYTE	%0_1111111
BYTE	%0_1000001
BYTE	%0_0000000
' J
' ....*
' ....*
' ....*
' ....*
' ....*
' *...*
' .***.
BYTE	%0_0100000
BYTE	%0_1000000
BYTE	%0_1000000
BYTE	%0_1000000
BYTE	%0_0111111
' K
' *...*
' *..*.
' *.*..
' **...
' *.*..
' *..*.
' *...*
BYTE	%0_1111111
BYTE	%0_0001000
BYTE	%0_0010100
BYTE	%0_0100010
BYTE	%0_1000001
' L
' *....
' *....
' *....
' *....
' *....
' *....
' *****
BYTE	%0_1111111
BYTE	%0_1000000
BYTE	%0_1000000
BYTE	%0_1000000
BYTE	%0_1000000
' M
' *...*
' **.**
' *.*.*
' *...*
' *...*
' *...*
' *...*
BYTE	%0_1111111
BYTE	%0_0000010
BYTE	%0_0000100
BYTE	%0_0000010
BYTE	%0_1111111
' N
' *...*
' **..*
' *.*.*
' *..**
' *...*
' *...*
' *...*
BYTE	%0_1111111
BYTE	%0_0000010
BYTE	%0_0000100
BYTE	%0_0001000
BYTE	%0_1111111
' O
' .***.
' *...*
' *...*
' *...*
' *...*
' *...*
' .***.
BYTE	%0_0111110
BYTE	%0_1000001
BYTE	%0_1000001
BYTE	%0_1000001
BYTE	%0_0111110
' P
' ****.
' *...*
' *...*
' ****.
' *....
' *....
' *....
BYTE	%0_1111111
BYTE	%0_0001001
BYTE	%0_0001001
BYTE	%0_0001001
BYTE	%0_0000110
' Q
' .***.
' *...*
' *...*
' *...*
' *.*.*
' *..**
' .****
BYTE	%0_0111110
BYTE	%0_1000001
BYTE	%0_1010001
BYTE	%0_1100001
BYTE	%0_1111110
' R
' ****.
' *...*
' *...*
' ****.
' *.*..
' *..*.
' *...*
BYTE	%0_1111111
BYTE	%0_0001001
BYTE	%0_0011001
BYTE	%0_0101001
BYTE	%0_1000110
' S
' .****
' *....
' *....
' .***.
' ....*
' ....*
' ****.
BYTE	%0_1000110
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_1001001
BYTE	%0_0110001
' T
' *****
' ..*..
' ..*..
' ..*..
' ..*..
' ..*..
' ..*..
BYTE	%0_0000001
BYTE	%0_0000001
BYTE	%0_1111111
BYTE	%0_0000001
BYTE	%0_0000001
' U
' *...*
' *...*
' *...*
' *...*
' *...*
' *...*
' .***.
BYTE	%0_0111111
BYTE	%0_1000000
BYTE	%0_1000000
BYTE	%0_1000000
BYTE	%0_0111111
' V
' *...*
' *...*
' *...*
' *...*
' *...*
' .*.*.
' ..*..
BYTE	%0_0011111
BYTE	%0_0100000
BYTE	%0_1000000
BYTE	%0_0100000
BYTE	%0_0011111
' W
' *...*
' *...*
' *...*
' *...*
' *.*.*
' *.*.*
' .***.
BYTE	%0_0111111
BYTE	%0_1000000
BYTE	%0_1110000
BYTE	%0_1000000
BYTE	%0_0111111
' X
' *...*
' *...*
' .*.*.
' ..*..
' .*.*.
' *...*
' *...*
BYTE	%0_1100011
BYTE	%0_0010100
BYTE	%0_0001000
BYTE	%0_0010100
BYTE	%0_1100011
' Y
' *...*
' *...*
' .*.*.
' ..*..
' ..*..
' ..*..
' ..*..
BYTE	%0_0000011
BYTE	%0_0000100
BYTE	%0_1111000
BYTE	%0_0000100
BYTE	%0_0000011
' Z
' *****
' ....*
' ...*.
' ..*..
' .*...
' *....
' *****
BYTE	%0_1100001
BYTE	%0_1010001
BYTE	%0_1001001
BYTE	%0_1000101
BYTE	%0_1000011
' [
' ...**
' ...*.
' ...*.
' ...*.
' ...*.
' ...*.
' ...**
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_1111111
BYTE	%0_1000001
' \
' .....
' *....
' .*...
' ..*..
' ...*.
' ....*
' .....
BYTE	%0_0000010
BYTE	%0_0000100
BYTE	%0_0001000
BYTE	%0_0010000
BYTE	%0_0100000
' ]
' **...
' .*...
' .*...
' .*...
' .*...
' .*...
' **...
BYTE	%0_1000001
BYTE	%0_1111111
BYTE	%0_0000000
BYTE	%0_0000000
BYTE	%0_0000000
' ^
' ..*..
' .*.*.
' .....
' .....
' .....
' .....
' .....
BYTE	%0_0000000
BYTE	%0_0000010
BYTE	%0_0000001
BYTE	%0_0000010
BYTE	%0_0000000
' _
' .....
' .....
' .....
' .....
' .....
' .....
' *****
BYTE	%0_1000000
BYTE	%0_1000000
BYTE	%0_1000000
BYTE	%0_1000000
BYTE	%0_1000000
