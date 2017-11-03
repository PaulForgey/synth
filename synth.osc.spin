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
    Param_Osc_Insn
    Param_In
    Param_Freq                                  ' [13]
    Param_Env           = Param_Freq + 13       ' [13]
    Param_Out           = Param_Env + 13        ' [2]

    Param_Max           = Param_Out + 2

    #0
    LFO_Sine
    LFO_Triangle
    LFO_SawUp
    LFO_SawDown
    LFO_Square
    LFO_Noise

    osc_len             = 23                    ' oscillators have 23 instructions each

OBJ
    tables      : "synth.tables"
    algs        : "synth.alg.table"

VAR
    LONG Cog_
    LONG Params_[Param_Max]

PUB Start(FreqsPtr, EnvsPtr, FbPtr, LFOBiasPtr, InPtr, OutPtr, LFOPtr, LFOShape, Waves, Alg) | insn, i, ptr, mod, sum, j, f, x
{{
Start oscillator bank on a cog
FreqsPtr:       word array of 13 frequency long pointers (fs/2=$8000_0000)
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

    insn := 0

    Params_[Param_Sines] := tables.SinePtr
    Params_[Param_Exps] := tables.ExpPtr
    Params_[Param_EGs] := tables.EGLogPtr
    Params_[Param_Fb] := FbPtr
    Params_[Param_LFO_Bias] := LFOBiasPtr
    Params_[Param_Osc_Insn] := @insn
    Params_[Param_In] := InPtr
    Params_[Param_Out] := OutPtr
    Params_[Param_Out+1] := LFOPtr

    ' patch LFO program
    ptr := @@(WORD[@LFOWaveTable][LFOShape])
    LONG[@lfo_wave][0] := LONG[ptr][0]
    ptr := @@(WORD[@LFOQuadrantTable][LFOShape])
    repeat i from 0 to 2
        LONG[@lfo_quad][i] := LONG[ptr][i]

    ' establish envelopes and frequencies
    ' 12 operators and 1 LFO
    repeat i from 0 to 12
        Params_[Param_Freq+i] := WORD[FreqsPtr][i]
        Params_[Param_Env+i] := WORD[EnvsPtr][i]
    
    Cog_ := cognew(@entry, @Params_) + 1
    if Cog_ == 0
        abort 1

    ' generate the oscillator code
    ptr := @BYTE[algs.AlgTablePtr][Alg * 6]
    repeat i from 0 to 11
        mod := BYTE[ptr][i // 6]
        f := mod & $80
        sum := (mod >> 4) & 7
        mod &= 7

        if i => 6
            if mod
                mod += 6
            if sum
                sum += 6

        repeat j from 0 to CONSTANT(osc_len-1)
            x := LONG[@osc0][j]
            case j
                0, 14: ' both s and d +osc
                    x += (i + (i << 9))
                1, 8: ' s +osc
                    x += i
                20, 22: ' d +osc
                    x += (i << 9)
                2: ' mod
                    x += mod
                3: ' fb
                    if f
                        x := feedback_op
                10: ' wave
                    if Waves & (1 << (i // 6))
                        x := triangle_w
                21: ' sum
                    x += (i << 9) + sum
            repeat while insn <> 0
            insn := x

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

    mov r1, #oscs
    mov r2, #(osc_len*12)
copy_oscs                           ' copy generated oscillator code
    rdlong r0, g_osc_insn wz        ' (can't copy nop instructions)
    if_z jmp #copy_oscs
    movd :copy0, r1
    wrlong zero, g_osc_insn         ' acknowledge it (not the fastest way to do this, but compact)
:copy0
    mov 0-0, r0                     ' copy oscillator instruction
    add r1, #1                      ' next one
    djnz r2, #copy_oscs             ' next instruction

    mov oscs_ret, jmp_loop          ' install jmp #loop at end of oscillators

    mov r3, #13                     ' clear outputs (avoid noise when re-initing)
    mov r2, #outs
:clear
    movd :clear0, r2
    add r2, #1
:clear0
    mov 0-0, #0
    djnz r3, #:clear

    mov fb, #0                      ' start with feedback parameter at 0

loop
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
    shl r0, #18                     ' envelope scale unscaled result
    shr r0, r1                      ' now scale from that (any consumers will round off the $3fff left)
    rdbyte fb, g_fb                 ' update global feedback
    negc r0, r0                     ' negate if needed
    add r0, lfo_bias                ' apply bias (envelope scale)
    wrlong r0, g_outs+1             ' write LFO output

lfo_skip
    shr lfsr, #1 wc                 ' advance noise generator
    if_c xor lfsr, lfsr_taps

    rdlong in, g_in                 ' update master input
    add in, outs+1                  ' sum the two op1 outputs (non destructively)
    add in, outs+7
    wrlong in, g_outs               ' send output

    waitpeq lrmask, lrmask

    rdlong lfo_bias, g_lfo_bias     ' update global LFO bias
    jmp #oscs                       ' update the oscillators

' constants
smask       long    $7fff_ffff      ' not the sign bit
lrmask      long    $00_20_00_00    ' DAC load, use to wait one sample
logmask     long    $3ff << 1       ' lookup table offset mask
s90         long    $4000_0000      ' phase counter bit indicating 90 degrees
lfsr_taps   long    $8020_0002      ' x^32+x^22+x^2+1
zero        long    $0              ' zero as a destination param for wrlong
jmp_loop    jmp #loop               ' jmp #loop instruction

' global state
lfsr        long    $1f0            ' noise register
lfo_bias    long    $2000_0000      ' LFO bias (initialized to center)

oscs        res     (osc_len*12)    ' generated code for 12 oscillators
oscs_ret    res     1               ' jmp #loop

in          res     1               ' master input
phases      res     13              ' 12 operators and an LFO
freqs       res     12              ' 12 operators (LFO reads directly from global)
outs        res     13              ' 12 operators and 1 zero

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
g_osc_insn  res     1               ' operator instruction to copy in
g_in        res     1               ' master audio input
g_freqs     res     13              ' frequency inputs: 12 operators, 1 LFO
g_envs      res     13              ' envelope inputs: 12 operators, 1 LFO
g_outs      res     2               ' oscillator output for audio, LFO

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
    shl r1, #22

' an oscillator
osc0
    add phases+0, freqs+0           ' phase += frequency
    mov r0, phases+0                ' establish working phase in r0
osc0_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc0_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+0             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc0_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+0, g_freqs+0 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+1, r0                 ' adjust result negative for bottom quandrants, store in osc output
osc0_sum                            ' patch: sum in source register
    add outs+1, outs+0              ' output += sum input
    if_z mov phases+0, #0           ' resync if frequency is zero

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

