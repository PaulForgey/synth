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

PUB AlgTablePtr
    return @AlgTable

DAT
AlgTable
' Each entry is a series of 6 operators layed out as:
' 76543210
' ||||||||
' |||||+++-: mod, 1 based, phase modulated by the output of this operator, or 0 for none
' ||||+----: fb source, used by UI only (ignored by osc), indicates this operator provides feedback
' |+++-----: sum, 1 based, output sums from the output of this operator, or 0 for none
' +--------: fb, this is the feedback operator

' Algorithm 1
'    6*
'    |
'    5
'    |
' 2  4
' |  |
' 1--3
BYTE $32, $00, $04, $05, $06, $86

' Algorithm 2
'    6
'    |
'    5
'    |
' 2* 4
' |  |
' 1--3
BYTE $32, $82, $04, $05, $06, $00

' Algorithm 3
' 
' 
'
' 
' 3  6*
' |  |
' 2  5
' |  |
' 1--4
BYTE $42, $03, $00, $05, $06, $86
 
' Algorithm 4
'
' 
' 
' 3  6<
' |  |
' 2  5
' |  |
' 1--4>
BYTE $42, $03, $00, $0d, $06, $84

' Algorithm 5
' 
' 
' 
' 
' 2  4  6*
' |  |  |
' 1--3--5
BYTE $32, $00, $54, $00, $06, $86

' Algorithm 6
' 
' 
' 
' 
'  2  4  6<
'  |  |  |
'  1--3--5>
BYTE $32, $00, $54, $00, $0e, $85

' Algorithm 7
' 
' 
'       6*
'       |
' 2  4--5
' |  |
' 1--3
BYTE $32, $00, $04, $50, $06, $86 

' Algorithm 8
' 
' 
'    6
'    |
' 2  5--4*
' |  |
' 1--3
BYTE $32, $00, $05, $84, $46, $00

' Algorithm 9
' 
' 
'    6
'    |
' 2* 5--4
' |  |
' 1--3
BYTE $32, $82, $05, $00, $46, $00
 
' Algorithm 10
' 
' 
' 3*
' |
' 2  5--6
' |  |
' 1--4
BYTE $42, $03, $83, $05, $60, $00

' Algorithm 11
' 
' 
' 3
' |
' 2  5--6*
' |  |
' 1--4
BYTE $42, $03, $00, $05, $60, $86

' Algorithm 12
' 
' 
' 
' 
' 2* 4--5--6
' |  |
' 1--3
BYTE $32, $82, $04, $50, $60, $00
 
' Algorithm 13
' 
' 
' 
' 
' 
' 2  4--5--6*
' 1--3
BYTE $32, $00, $04, $50, $60, $86

' Algorithm 14
' 
'
'    5--6*
'    |
' 2  4
' |  |
' 1--3
BYTE $32, $00, $04, $05, $60, $86

' Algorithm 15
'
'
'    5--6
'    |
' 2* 4
' |  |
' 1--3
BYTE $32, $82, $04, $05, $60, $00

' Algorithm 16
'
' 
' 6* 4
' |  |
' 5--3--2
' |
' 1
BYTE $05, $00, $24, $00, $36, $86

' Algorithm 17
'
' 
' 6  4
' |  |
' 5--3--2*
' |
' 1
BYTE $05, $82, $24, $00, $36, $00

' Algorithm 18
' 6
' |
' 5
' |
' 4--2--3*
' |
' 1
BYTE $04, $30, $83, $25, $06, $00

' Algorithm 19
'
' 
' 3
' |
' 2  6*
' |  |--|
' 1--4--5
BYTE $42, $03, $00, $56, $06, $86

' Algorithm 20
' 
' 
' 
' 
' 3*    5--6
' |--|  |
' 1--2--4
BYTE $23, $43, $83, $05, $60, $00

' Algorithm 21
' 
' 
' 
' 
' 3*    6  
' |--|  |--|
' 1--2--4--5
BYTE $23, $43, $83, $56, $06, $00

' Algorithm 22
' 
' 
' 
' 
' 2  6*
' |  |--|--|
' 1--3--4--5
BYTE $32, $00, $46, $56, $06, $86

' Algorithm 23
' 
' 
' 
' 
'    3  6*
'    |  |--|
' 1--2--4--5
BYTE $20, $43, $00, $56, $06, $86

' Algorithm 24
' 
' 
' 
' 
'       6*
'       |--|--|
' 1--2--3--4--5
BYTE $20, $30, $46, $56, $06, $86

' Algorithm 25
' 
' 
' 
' 
'          6*
'          |--|
' 1--2--3--4--5
BYTE $20, $30, $40, $56, $06, $86
  
' Algorithm 26
' 
' 
' 
' 
'    3  5--6*
'    |  |
' 1--2--4
BYTE $20, $43, $00, $05, $60, $86

' Algorithm 27
' 
' 
' 
' 
'    3* 5--6
'    |  |
' 1--2--4
BYTE $20, $43, $83, $05, $60, $00

' Algorithm 28
' 
' 
'    5*
'    |
' 2  4
' |  |
' 1--3--6
BYTE $32, $00, $64, $05, $85, $00

' Algorithm 29
' 
' 
' 
' 
'       4  6*
'       |  |
' 1--2--3--5
BYTE $20, $30, $54, $00, $06, $86

' Algorithm 30
' 
' 
'       5*
'       |
'       4
'       |
' 1--2--3--6
BYTE $20, $30, $64, $05, $85, $00

' Algorithm 31
' 
' 
' 
' 
'             6*
'             |
' 1--2--3--4--5
BYTE $20, $30, $40, $50, $06, $86

' Algorithm 32
' 
' 
' 
' 
' 
' 
' 1--2--3--4--5--6*
BYTE $20, $30, $40, $50, $60, $86
