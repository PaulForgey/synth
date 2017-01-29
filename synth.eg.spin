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
    ' envelope generators
    #0
    EG_Level
    EG_Goal
    EG_Rate
    EG_Freq
    EG_LogLevel
    EG_Max

    #0
    Param_EGLogs
    Param_Pitches
    Param_PitchBend
    Param_Biases
    Param_OscPitches
    Param_EG
    Param_Audio
    Param_Max

    DAC_LeftLineIn      = 0 << 9
    DAC_RightLineIn     = 1 << 9
    DAC_LeftHPOut       = 2 << 9
    DAC_RigthHPOut      = 3 << 9
    DAC_Analog          = 4 << 9
    DAC_Digital         = 5 << 9
    DAC_Power           = 6 << 9
    DAC_IF              = 7 << 9
    DAC_Sample          = 8 << 9
    DAC_Active          = 9 << 9
    DAC_Reset           = $f << 9

OBJ
    tables      : "synth.tables"    

VAR
    LONG Cog_
    LONG Params_[Param_Max]
    LONG EG_[EG_Max * 28]
    LONG OscPitches_[24]

PUB Start(BendPtr, Biases, AudioPtr) | e
{{
BendPtr     : long pointer to global pitch bend value, signed +/- $2000_0000 (+/- 16 octaves)
Biases      : word array of 7 envelope bias pointer and scale entries (14 words total)
AudioPtr    : optional audio output
}}
    Stop
    Params_[0] := tables.EGLogPtr
    Params_[1] := tables.PitchPtr
    Params_[2] := BendPtr
    Params_[3] := Biases
    Params_[4] := @OscPitches_
    Params_[5] := @EG_
    Params_[6] := AudioPtr

    LongFill(@OscPitches_, !0, 24)

    Cog_ := cognew(@entry, @Params_) + 1
    if Cog_ == 0
        abort 2

PUB Stop
    if Cog_
        cogstop(Cog_ - 1)
    Cog_ := 0

PUB EgPtr(e, p)
{{
Returns long pointer to EG for envelope
e           : envelope to return pointer in (0-27)
p           : param within the EG
}}
    return @EG_[e * EG_Max + p]

PUB SetEg(e, p, v)
{{
Set EG paramter
e           : envelope to set (0-27)
p           : param within the EG
v           : value to set
}}
    EG_[e * EG_Max + p] := v

PUB OscPitches(p)
{{
Return pointer to LONG array of 6 pitch values for a given group
p           : voice (0-3)
}}
    return @OscPitches_[p*6]

{{
Initialize the DAC
CsbPin      : pin assigned to the DAC's control I2C CS
ClkPin      : pin assigned to the DAC's master clock
}}
PUB InitDAC(CsbPin, ClkPin) | csb
    csb := (1 << CsbPin)
    
    DIRA |= (csb | (1 << ClkPin))
    CTRA := CONSTANT( %10_100 << 23 ) | ClkPin  ' PLL /8 single ended    
    FRQA := $1210_385d

    ' reset
    ControlDAC( DAC_Reset, csb )
    ' power up
    ControlDAC( CONSTANT(DAC_Power | %0011_0111), csb )
    ' set 44.1K, 256x base oversample (11.2896 MHz master clock)
    ControlDAC( CONSTANT(DAC_Sample | %00_1000_00), csb )
    ' set 20 bit DSP mode A
    ControlDAC( CONSTANT(DAC_IF | %0001_01_11), csb )
    ' select DAC
    ControlDAC( CONSTANT(DAC_Analog | %10010), csb )
    ' unmute
    ControlDAC( CONSTANT(DAC_Digital | 0), csb )
    ' activate
    ControlDAC( CONSTANT(DAC_Active | 1), csb )
    ' power up outputs
    ControlDAC( CONSTANT(DAC_Power | %0010_0111), csb )

PRI ControlDAC(v, csb)
{{
Send a 16-bit word to the DAC's control I2c interface
15..9       : register
8..0        : value
}}
    OUTA &= !csb
    repeat 16
        OUTA &= CONSTANT(!%10)
        if v & $8000
            OUTA |= 1
        else
            OUTA &= CONSTANT(!1)
        OUTA |= %10
        v <<= 1
    OUTA |= csb

DAT
    org

entry
    mov r0, PAR                     ' read all the pointers
    rdword g_eg, r0                 ' eglog table
    add r0, #4
    rdword g_pitch, r0              ' pitch table
    add r0, #4
    rdword g_bend, r0               ' global pitch bend pointer
    add r0, #4
    rdword g_biases, r0             ' bias array
    add r0, #4
    rdword g_pitches, r0            ' osc pitches
    add r0, #4
    rdword g_egs, r0                ' table of EGs    
    add r0, #4
    rdword g_audio, r0 wz           ' optional audio output
    if_z jmp #loop

    or DIRA, dacmask
    movs VCFG, #%00110000           ' use only pins 4..5 in the group
    movd VCFG, #2                   ' on pin group 2 (16-23)
    movi VCFG, #%01_00_0_000        ' VGA 2 color
    mov FRQA, bclk
    movs CTRA, #22
    movi CTRA, #%010_010            ' PLL single ended (BCLK) @ PLL/32 (VCO/2) = fs*64

loop
    rdlong bendw, g_bend            ' update global bend value
    mov ptr, g_egs                  ' reset pointers
    mov pptr, g_pitches
    mov c0, #4                      ' iterate 4 groups of 7

egloop
    testn g_audio, #0 wz            ' do we lead or follow the DAC output?
    if_z waitpeq lrmask, lrmask
    if_z jmp #:eg

    rdlong audio, g_audio
    maxs audio, hi
    mins audio, lo    
    rev audio, #12
    mov VSCL, startvscl
    waitvid lcolors, #0
    mov VSCL, dacvscl
    waitvid rcolors, audio

:eg
    ' 1 pitch EG
    ' [nop]
    mov bptr, g_biases              ' point at first bias entry
    rdlong level, ptr               ' read level
    add ptr, #4                     ' point at goal
    ' [nop]
    rdlong delta, ptr               ' read goal
    add ptr, #4                     ' point at rate
    sub delta, level                ' delta = goal-level
    rdlong rate, ptr                ' read rate
    abs delta, delta wc             ' |delta| save sign
    sub ptr, #4*2                   ' point back at level
    rdword bias, bptr               ' read bias pointer
    add bptr, #2                    ' point at scale
    max delta, rate                 ' limit delta to rate
    rdbyte scale, bptr              ' read scale
    negc delta, delta               ' restore sign
    add level, delta                ' move level
    rdlong bias, bias               ' read bias value
    sub bias, pitch0                ' move unsigned bias range to signed offset
    sar bias, scale                 ' scale bias
    wrlong level, ptr               ' write back unbiased (current) level
    add level, bias                 ' apply bias
    sub level, pitch0               ' move positive range to signed offset
    mov bend, bendw                 ' working copy of bend value from global pitch bend value
    add bend, level                 ' add it to our signed offset
    add ptr, #5*4                   ' point at next eg
    add bptr, #2                    ' point at next bias entry
    mov c1, #6                      ' iterate 6 operators

oploop
    ' 6 operator EGs, pitch offset by output of pitch EG we just ran
    rdlong pitch, pptr              ' read pitch units (1024 per octave, actual value << 14, higher value is lower freq)
    add pptr, #4                    ' next pitch entry
    add pitch, bend                 ' offset pitch+=(pitch bend + pitch EG)
    rdlong level, ptr               ' read current level
    add ptr, #4                     ' move to goal
    shr pitch, #13                  ' shift from EG friendly value to long offset
    rdlong delta, ptr               ' read goal (soon to be delta)
    add ptr, #4                     ' move to rate
    mov r0, pitch                   ' save a copy of pitch
    rdlong rate, ptr                ' read rate
    sub ptr, #4*2                   ' move back to level
    and r0, pitchmask               ' mask pitch table offset
    rdword bias, bptr               ' read bias pointer
    add bptr, #2                    ' move to scale
    sub delta, level                ' delta = goal-level
    rdbyte scale, bptr              ' read scale
    abs delta, delta wc             ' |delta| saving original sign
    add r0, g_pitch                 ' offset += pitch table
    rdlong bias, bias               ' read -bias (larger moves envelope down)
    shr bias, scale                 ' scale bias
    max delta, rate                 ' limit delta to the rate   
    rdlong r0, r0                   ' read high octave frequency
    negc delta, delta               ' restore sign
    add level, delta                ' move level
    wrlong level, ptr               ' write back current level
    add bptr, #2                    ' point at next bias entry
    shr pitch, #12                  ' isolate octave (from longs)
    max bias, level                 ' do not bias level < 0
    sub level, bias                 ' bias the level before log lookup
    add ptr, #4*3                   ' now point at frequency
    shr r0, pitch                   ' shift to proper octave
    wrlong r0, ptr                  ' write back frequency
    shr level, #19                  ' whole part of level (in words)
    add level, g_eg                 ' offset += eg log table
    rdword level, level             ' r0 = log(r0)
    add ptr, #4                     ' point at loglevel
    ' [nop]
    wrlong level, ptr               ' write loglevel
    add ptr, #4                     ' point to next eg

    djnz c1, #oploop                ' next operator
    djnz c0, #egloop                ' next group
    jmp #loop                       ' next cycle

logmask         long    $3ff << 1
pitchmask       long    $3ff << 2
pitch0          long    $2000_0000      ' unsigned bias offset from envelope midpoint to 0
bclk            long    $1210_385d      ' 5_644_800 * 16 / 32 = 2_822_400 (fs*64)
dacmask         long    $00_70_00_00
dacvscl         long    (1 << 12) | 63  ' dac+start=64 BCLKs
startvscl       long    (1 << 12) | 1
lcolors         long    %0011_0000_0010_0000
rcolors         long    %0001_0000_0000_0000
lrmask          long    $00_20_00_00
hi              long    $000f_ffff
lo              long    $fff0_0001

g_eg            res     1
g_pitch         res     1
g_bend          res     1
g_pitches       res     1
g_biases        res     1
g_egs           res     1
g_audio         res     1
ptr             res     1
bptr            res     1
pptr            res     1
r0              res     1
c0              res     1
c1              res     1
pitch           res     1
rate            res     1
delta           res     1
level           res     1
bias            res     1
scale           res     1
bend            res     1
bendw           res     1
audio           res     1
