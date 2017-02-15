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
    #0
    Param_Sines
    Param_EGs
    Param_Exps
    Param_Fb
    Param_LFO_Bias
    Param_Master_In

    Param_Freq
    Param_Env           = Param_Freq + 13
    Param_Out           = Param_Env + 13
    Param_In            = Param_Out + 13
    Param_Mod           = Param_In + 12

    Param_Max           = Param_Mod + 12

    #0
    LFO_Sine
    LFO_Triangle
    LFO_SawUp
    LFO_SawDown
    LFO_Square
    LFO_Noise

OBJ
    tables      : "synth.tables"
    algs        : "synth.alg.table"

VAR
    LONG Cog_
    LONG OpValues_[16]
    LONG Params_[Param_Max]

PUB Start(Freqs, EnvsPtr, FbPtr, LFOBiasPtr, InPtr, OutPtr, LFOPtr, LFOShape, Waves, Alg) | i, ptr, mod, sum, j
{{
Start oscillator bank on a cog
Freqs:          word array of 13 frequency long pointers (fs/2=$8000_0000)
EnvsPtr:        word array of 13 envelope word pointers 
FbPtr:          byte pointer to global feedback value
LFOBiasPtr:     long pointer to unsigned bias value centered at $2000_0000
InPtr:          long pointer to audio input
OutPtr:         long pointer to audio output
LFOPtr:         LFO output long pointer
LFOShape:       LFO waveshape (LFO_Sine-LFO_Noise)
Waves:          BYTE value bit array of waveshapes, osc0-7 repeated osc8-11
Alg:            algorithm to arrange oscillators in (0-31)
}}
    Stop

    Params_[Param_Sines] := tables.SinePtr
    Params_[Param_Exps] := tables.ExpPtr
    Params_[Param_EGs] := tables.EGLogPtr
    Params_[Param_Fb] := FbPtr
    Params_[Param_LFO_Bias] := LFOBiasPtr
    Params_[Param_Master_In] := InPtr

    ' patch LFO program
    ptr := @@(WORD[@LFOWaveTable][LFOShape])
    LONG[@lfo_wave][0] := LONG[ptr][0]
    ptr := @@(WORD[@LFOQuadrantTable][LFOShape])
    repeat i from 0 to 2
        LONG[@lfo_quad][i] := LONG[ptr][i]

    ' sine vs. triangle waves
    repeat i from 0 to 5
        if Waves & (1 << i)
            j := triangle_w
        else
            j := sine_w
        LONG[ @@(WORD[@WaveTable][i<<1]) ] := j
        LONG[ @@(WORD[@WaveTable][(i<<1)+1]) ] := j

    ' establish envelopes and frequencies
    ' 12 operators and 1 LFO
    repeat i from 0 to 12
        Params_[Param_Freq+i] := WORD[Freqs][i]
        Params_[Param_Env+i] := WORD[EnvsPtr][i]
    
    ' outputs of operators
    repeat i from 0 to 5
        Params_[Param_Out+i] := @OpValues_[i+1]     ' keep virtual operator zero's index pointing to a zero
        Params_[Param_Out+i+6] := @OpValues_[i+9]
    
    ' output of operator 1, the one we hear
    Params_[Param_Out] := OutPtr

    ' LFO output
    Params_[Param_Out+12] := LFOPtr

    ' arrange the algorithm
    ptr := @BYTE[algs.AlgTablePtr][Alg * 6]
    repeat i from 0 to 5
        mod := BYTE[ptr++]

        ' designated feedback operator has MSB set
        if mod & $80
            j := feedback_op
        else
            j := normal_op

        LONG[ @@(WORD[@FbTable][i<<1]) ] := j
        LONG[ @@(WORD[@FbTable][(i<<1)+1]) ] := j

        ' high nibble is operator to sum output from
        sum := (mod >> 4) & $7
        ' low nibble is operator to modulate from
        mod &= $7

        Params_[Param_Mod+i] := @OpValues_[mod]
        Params_[Param_Mod+i+6] := @OpValues_[8+mod]

        Params_[Param_In+i] := @OpValues_[sum]
        if sum == 7
            Params_[Param_In+i+6] := InPtr
        else
            Params_[Param_In+i+6] := @OpValues_[8+sum]

    Cog_ := cognew(@entry, @Params_) + 1
    if Cog_ == 0
        abort 1

PUB Stop
    if (Cog_)
        cogstop(Cog_ - 1)
    Cog_ := 0
    
DAT
    org

entry
    mov r1, PAR                     ' copy parameters
    mov r2, #params                 ' starting destination register
    mov r3, #Param_Max              ' number of registers
:param
    rdlong r0, r1                   ' read parameter from global memory
    add r1, #4                      ' increment global memory pointer
    movd :param0, r2                ' set where to write parameter
    add r2, #1                      ' next register
:param0
    mov 0-0, r0                     ' write parameter
    djnz r3, #:param                ' loop

    mov fb, #0                      ' start with feedback parameter at 0    

loop
    ' the oscillators are unrolled 12 times over. Only the first instance will be commented
    ' (macro assembly would be rather nice)
    
    ' oscillator 0
    '
    rdlong r0, g_freqs+0 wz         ' read frequency (fs/2 = $8000_0000)
    add phases+0, r0                ' advance phase state
    mov r0, phases+0                ' working phase state
    rdlong r1, g_mods+0             ' modulation value
osc0_fb                             ' next instruction is patched to shl r1, fb for feedback operators
    shl r1, #18                     ' scale: +/- 1 as one full rotation either direction
    add r0, r1                      ' add modulation to working state
    rdword r2, g_envs+0             ' read envelope in 4.10 << 1
    if_z mov phases+0, #0           ' resync oscillator if freq == 0
    test r0, s90 wz                 ' orient within proper point in quarter arc
    negnz r0, r0 wc                 ' flip in second half of quadrant, c now set if so
    and r0, smask                   ' remove sign bit
    shr r0, #19                     ' shift-1 to word offset. rdword will also ignore LSB
osc0_w
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0 = log(sin(r0)). output format is 4.10 << 1
    add r0, r2                      ' apply envelope
    mov r1, r0                      ' save a copy
    wrlong outs+0, g_outs+0         ' write prior output (and after reading modulation input)
    and r0, logmask                 ' isolate lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0). output format is in 1.n >> int(log_value)
    shr r1, #11                     ' shift+1 from word offset
    shr r0, r1                      ' scale non-fractional part
    rdlong outs+0, g_ins+0          ' read summation input
    negc r0, r0                     ' adjust result negative if phase was negative
    add outs+0, r0                  ' write this output next time around

    ' oscillator 1
    '
    rdlong r0, g_freqs+1 wz
    add phases+1, r0
    mov r0, phases+1
    rdlong r1, g_mods+1
osc1_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+1
    if_z mov phases+1, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc1_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+1, g_outs+1
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+1, g_ins+1
    negc r0, r0
    add outs+1, r0

    ' oscillator 2
    '
    rdlong r0, g_freqs+2 wz
    add phases+2, r0
    mov r0, phases+2
    rdlong r1, g_mods+2
osc2_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+2
    if_z mov phases+2, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc2_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+2, g_outs+2
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+2, g_ins+2
    negc r0, r0
    add outs+2, r0

    ' oscillator 3
    '
    rdlong r0, g_freqs+3 wz
    add phases+3, r0
    mov r0, phases+3
    rdlong r1, g_mods+3
osc3_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+3
    if_z mov phases+3, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc3_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+3, g_outs+3
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+3, g_ins+3
    negc r0, r0
    add outs+3, r0

    ' oscillator 4
    '
    rdlong r0, g_freqs+4 wz
    add phases+4, r0
    mov r0, phases+4
    rdlong r1, g_mods+4
osc4_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+4
    if_z mov phases+4, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc4_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+4, g_outs+4
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+4, g_ins+4
    negc r0, r0
    add outs+4, r0

    ' oscillator 5
    '
    rdlong r0, g_freqs+5 wz
    add phases+5, r0
    mov r0, phases+5
    rdlong r1, g_mods+5
osc5_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+5
    if_z mov phases+5, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc5_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+5, g_outs+5
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+5, g_ins+5
    negc r0, r0
    add outs+5, r0

    ' oscillator 6
    '
    rdlong r0, g_freqs+6 wz
    add phases+6, r0
    mov r0, phases+6
    rdlong r1, g_mods+6
osc6_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+6
    if_z mov phases+6, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc6_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+6, g_outs+6
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+6, g_ins+6
    negc r0, r0
    add outs+6, r0


    ' oscillator 7
    '
    rdlong r0, g_freqs+7 wz
    add phases+7, r0
    mov r0, phases+7
    rdlong r1, g_mods+7
osc7_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+7
    if_z mov phases+7, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc7_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+7, g_outs+7
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+7, g_ins+7
    negc r0, r0
    add outs+7, r0

    ' oscillator 8
    '
    rdlong r0, g_freqs+8 wz
    add phases+8, r0
    mov r0, phases+8
    rdlong r1, g_mods+8
osc8_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+8
    if_z mov phases+8, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc8_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+8, g_outs+8
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+8, g_ins+8
    negc r0, r0
    add outs+8, r0

    ' oscillator 9
    '
    rdlong r0, g_freqs+9 wz
    add phases+9, r0
    mov r0, phases+9
    rdlong r1, g_mods+9
osc9_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+9
    if_z mov phases+9, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc9_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+9, g_outs+9
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+9, g_ins+9
    negc r0, r0
    add outs+9, r0

    ' oscillator 10
    '
    rdlong r0, g_freqs+10 wz
    add phases+10, r0
    mov r0, phases+10
    rdlong r1, g_mods+10
osc10_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+10
    if_z mov phases+10, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc10_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+10, g_outs+10
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+10, g_ins+10
    negc r0, r0
    add outs+10, r0

    ' oscillator 11
    '
    rdlong r0, g_freqs+11 wz
    add phases+11, r0
    mov r0, phases+11
    rdlong r1, g_mods+11
osc11_fb
    shl r1, #18
    add r0, r1
    rdword r2, g_envs+11
    if_z mov phases+11, #0
    test r0, s90 wz
    negnz r0, r0 wc
    and r0, smask
    shr r0, #19
osc11_w
    add r0, g_sine
    rdword r0, r0
    add r0, r2
    mov r1, r0
    wrlong outs+11, g_outs+11
    and r0, logmask
    add r0, g_exp
    rdword r0, r0
    shr r1, #11
    shr r0, r1
    rdlong outs+11, g_ins+11
    negc r0, r0
    add outs+11, r0

    ' LFO
    ' 
    rdlong r0, g_freqs+12           ' read LFO frequency
    add phases+12, r0 wc            ' increment LFO phase
    mov r0, phases+12               ' working phase
    rdword r2, g_envs+12            ' read EG value

lfo_quad
    test r0, s90 wz                 ' patchable: quadrant handling
    negnz r0, r0 wc                 ' patchable: quadrant handling
    nop                             ' patchable: quadrant handling

    and r0, smask                   ' drop sign
    shr r0, #19                     ' word offset into lookup

lfo_wave
    add r0, g_sine                  ' patchable: waveform

    rdword r0, r0                   ' lookup waveform
    add r0, r2                      ' add envelope
    mov r1, r0                      ' save a copy
    and r0, logmask                 ' mask in table offsert
    add r0, g_exp                   ' exponent table
    shr r1, #11                     ' isolate whole part of log
    ' [nop]
    rdword r0, r0                   ' r0=exp(r0) << scale
    shl r0, #14                     ' envelope scale unscaled result
    shr r0, r1                      ' now scale from that (any consumers will round off the $3fff left)
    rdbyte fb, g_fb                 ' update global feedback
    negc r0, r0                     ' negate if needed
    add r0, lfo_bias                ' apply bias (envelope scale)
    wrlong r0, g_outs+12            ' write LFO output

lfo_skip
    shr lfsr, #1 wc                 ' advance noise generator
    if_c xor lfsr, lfsr_taps

    rdlong in, g_in                 ' update master input
    add outs+0, outs+6              ' sum the two op1 outputs..
    add outs+0, in                  ' ..together and from master input

    rdlong lfo_bias, g_lfo_bias     ' update global LFO bias
    ' LFO+misc = 152 clocks
    ' 128 * 12 + 152 = 1688; 126 to spare

    waitpeq lrmask, lrmask
    jmp #loop

' constants
smask       long    $7fff_ffff      ' not the sign bit
lrmask      long    $00_20_00_00    ' DAC load, use to wait one sample
logmask     long    $3ff << 1       ' lookup table offset mask
s90         long    $4000_0000      ' phase counter bit indicating 90 degrees
lfsr_taps   long    $8020_0002      ' x^32+x^22+x^2+1

' global state
' oscillator state values are initialized to prevent noise on startup
phases      long    0[13]           ' 12 operators and an LFO
outs        long    0[12]
lfsr        long    $1f0            ' noise register
lfo_bias    long    $2000_0000      ' LFO bias (initialized to center)
in          long    0               ' master input

' working registers
r0          res     1
r1          res     1
r2          res     1
r3          res     1
fb          res     1

' parameters
params
g_sine      res     1               ' sine table
g_eglog     res     1               ' EG log table (used for LFO triangle/saw waveforms)
g_exp       res     1               ' exponent table
g_fb        res     1               ' global feedback scale
g_lfo_bias  res     1               ' global LFO bias
g_in        res     1               ' master audio input
g_freqs     res     13              ' frequency inputs: 12 operators, 1 LFO
g_envs      res     13              ' envelope inputs: 12 operators, 1 LFO
g_outs      res     13              ' oscillator output for audio, modulation input or summation input (last is LFO)
g_ins       res     12              ' summation inputs, often from location of '0' constant, otherwise one other oscillator output
g_mods      res     12              ' modulator inputs (tie to oscillator outputs)

            fit

lfo_sin_q
lfo_triangle_q                      ' patch for sine and triangle
    test r0, s90 wz                 ' first and third quandrants -> z
    negnz r0, r0 wc                 ' negate phase in first and third, result in third and fourth
    nop

' "up" and "down" are inverted concepts as higher bias values bring pitch and amplitude EGs down
lfo_sawdn_q                         ' patch for sawtooth, going down (oscillator values going up)
    test r0, s90 wc                 ' second and fourth quadrants -> c
    negc r0, r0                     ' negate both phase and result if so
    nop

lfo_sawup_q                         ' patch for sawtooth, going up (oscillator values going down)
    xor r0, smask                   ' ones complement (sign bit will be thrown away, so smask works for this)
    test r0, s90 wc                 ' second and fourth quadrants (after negation) -> c
    negc r0, r0                     ' negate both phase and result if so

lfo_sqr_q                           ' patch for square wave
    mov r0, r0 wc, nr               ' third and fourth quadrants -> c
    mov r0, s90                     ' output 1, negated in third and fourth
    nop    

lfo_sh_q                            ' patch for sample and hold (noise)
    if_nc jmp #lfo_skip             ' if we didn't cross into next period, stay where we are
    mov r0, lfsr wc                 ' read a random 32 bit signed value, negate result if signed
    andn r0, s90                    ' stay within first quadrant (note we never hit exactly 1)

sine_w                              ' patch for sine output
    add r0, g_sine                  ' sine table
triangle_w                          ' patch for non-sine linear outputs
    add r0, g_eglog                 ' log table

feedback_op                         ' patch for feedback operator
    shl r1, fb
normal_op                           ' patch for normal, non feedback operator
    shl r1, #18

LFOWaveTable
WORD    @sine_w
WORD    @triangle_w
WORD    @triangle_w
WORD    @triangle_w
WORD    @triangle_w
WORD    @triangle_w

LFOQuadrantTable
WORD    @lfo_sin_q
WORD    @lfo_triangle_q
WORD    @lfo_sawup_q
WORD    @lfo_sawdn_q
WORD    @lfo_sqr_q
WORD    @lfo_sh_q

FbTable
WORD    @osc0_fb, @osc6_fb
WORD    @osc1_fb, @osc7_fb
WORD    @osc2_fb, @osc8_fb
WORD    @osc3_fb, @osc9_fb
WORD    @osc4_fb, @osc10_fb
WORD    @osc5_fb, @osc11_fb

WaveTable
WORD    @osc0_w, @osc6_w
WORD    @osc1_w, @osc7_w
WORD    @osc2_w, @osc8_w
WORD    @osc3_w, @osc9_w
WORD    @osc4_w, @osc10_w
WORD    @osc5_w, @osc11_w
