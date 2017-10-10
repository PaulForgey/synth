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
    Param_In

    Param_Freq                                  ' [13]
    Param_Env           = Param_Freq + 13       ' [13]
    Param_Out           = Param_Env + 13        ' [1]

    Param_Max           = Param_Out + 2

    #0
    LFO_Sine
    LFO_Triangle
    LFO_SawUp
    LFO_SawDown
    LFO_Square
    LFO_Noise

    outs                = $1e0

OBJ
    tables      : "synth.tables"
    algs        : "synth.alg.table"

VAR
    LONG Cog_
    LONG Params_[Param_Max]

PUB Start(FreqsPtr, EnvsPtr, FbPtr, LFOBiasPtr, InPtr, OutPtr, LFOPtr, LFOShape, Waves, Alg) | i, ptr, mod, sum, j
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

    Params_[Param_Sines] := tables.SinePtr
    Params_[Param_Exps] := tables.ExpPtr
    Params_[Param_EGs] := tables.EGLogPtr
    Params_[Param_Fb] := FbPtr
    Params_[Param_LFO_Bias] := LFOBiasPtr
    Params_[Param_In] := InPtr
    Params_[Param_Out] := OutPtr
    Params_[Param_Out+1] := LFOPtr

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
        Params_[Param_Freq+i] := WORD[FreqsPtr][i]
        Params_[Param_Env+i] := WORD[EnvsPtr][i]
    
    ' arrange the algorithm
    ptr := @BYTE[algs.AlgTablePtr][Alg * 6]
    repeat i from 0 to 5
        mod := BYTE[ptr++]

        ' designated feedback operator has MSB set
        if mod & $80
            j := feedback_op
        else
            j := normal_op

        ' patch feedback vs normal operator shift instructions
        LONG[ @@(WORD[@FbTable][i<<1]) ] := j
        LONG[ @@(WORD[@FbTable][(i<<1)+1]) ] := j

        ' high nibble is operator to sum output from
        sum := ((mod >> 4) & $7) + outs
        ' low nibble is operator to modulate from
        mod := (mod & $7) + outs

        ' patch source registers of mod and sum instructions
        j := @@(WORD[@SumTable][i<<1]) 
        LONG[j] := LONG[j] & CONSTANT(!$1ff) | sum
        j := @@(WORD[@SumTable][(i<<1)+1]) 
        LONG[j] := LONG[j] & CONSTANT(!$1ff) | (sum+7)

        j := @@(WORD[@ModTable][i<<1]) 
        LONG[j] := LONG[j] & CONSTANT(!$1ff) | mod
        j := @@(WORD[@ModTable][(i<<1)+1]) 
        LONG[j] := LONG[j] & CONSTANT(!$1ff) | (mod+7)

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

    mov r3, #13                     ' clear outputs (avoid noise when re-initing)
    mov r2, #outs
:clear
    movd :clear0, r2
    add r2, #1
:clear0
    mov 0-0, #0
    djnz r3, #:clear

loop
    ' the oscillators are unrolled 12 times over
    ' (macro assembly would be rather nice)
    
    ' oscillator 0 (op1)
    '
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
    ' nop

    ' oscillator 1 (op2)
    '
    add phases+1, freqs+1           ' phase += frequency
    mov r0, phases+1                ' establish working phase in r0
osc1_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc1_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+1             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc1_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+1, g_freqs+1 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+2, r0                 ' adjust result negative for bottom quandrants, store in osc output
osc1_sum                            ' patch: sum in source register
    add outs+2, outs+0              ' output += sum input
    if_z mov phases+1, #0           ' resync if frequency is zero
    ' nop

    ' oscillator 2 (op3)
    '
    add phases+2, freqs+2           ' phase += frequency
    mov r0, phases+2                ' establish working phase in r0
osc2_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc2_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+2             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc2_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+2, g_freqs+2 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+3, r0                 ' adjust result negative for bottom quandrants, store in osc output
osc2_sum                            ' patch: sum in source register
    add outs+3, outs+0              ' output += sum input
    if_z mov phases+2, #0           ' resync if frequency is zero
    ' nop

    ' oscillator 3 (op4)
    '
    add phases+3, freqs+3           ' phase += frequency
    mov r0, phases+3                ' establish working phase in r0
osc3_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc3_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+3             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc3_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+3, g_freqs+3 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+4, r0                 ' adjust result negative for bottom quandrants, store in osc output
osc3_sum                            ' patch: sum in source register
    add outs+4, outs+0              ' output += sum input
    if_z mov phases+3, #0           ' resync if frequency is zero
    ' nop

    ' oscillator 4 (op5)
    '
    add phases+4, freqs+4           ' phase += frequency
    mov r0, phases+4                ' establish working phase in r0
osc4_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc4_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+4             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc4_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+4, g_freqs+4 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+5, r0                 ' adjust result negative for bottom quandrants, store in osc output
osc4_sum                            ' patch: sum in source register
    add outs+5, outs+0              ' output += sum input
    if_z mov phases+4, #0           ' resync if frequency is zero
    ' nop

    ' oscillator 5 (op6)
    '
    add phases+5, freqs+5           ' phase += frequency
    mov r0, phases+5                ' establish working phase in r0
osc5_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc5_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+5             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc5_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+5, g_freqs+5 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+6, r0                 ' adjust result negative for bottom quandrants, store in osc output
osc5_sum                            ' patch: sum in source register
    add outs+6, outs+0              ' output += sum input
    if_z mov phases+5, #0           ' resync if frequency is zero
    ' nop

    ' oscillator 6 (op1)
    '
    add phases+6, freqs+6           ' phase += frequency
    mov r0, phases+6                ' establish working phase in r0
osc6_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc6_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+6             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc6_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+6, g_freqs+6 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+8, r0                 ' adjust result negative for bottom quandrants, store in osc output
osc6_sum                            ' patch: sum in source register
    add outs+8, outs+0              ' output += sum input
    if_z mov phases+6, #0           ' resync if frequency is zero
    ' nop

    ' oscillator 7 (op2)
    '
    add phases+7, freqs+7           ' phase += frequency
    mov r0, phases+7                ' establish working phase in r0
osc7_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc7_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+7             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc7_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+7, g_freqs+7 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+9, r0                 ' adjust result negative for bottom quandrants, store in osc output
osc7_sum                            ' patch: sum in source register
    add outs+9, outs+0              ' output += sum input
    if_z mov phases+7, #0           ' resync if frequency is zero
    ' nop

    ' oscillator 8 (op3)
    '
    add phases+8, freqs+8           ' phase += frequency
    mov r0, phases+8                ' establish working phase in r0
osc8_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc8_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+8             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc8_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+8, g_freqs+8 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+10, r0                ' adjust result negative for bottom quandrants, store in osc output
osc8_sum                            ' patch: sum in source register
    add outs+10, outs+0             ' output += sum input
    if_z mov phases+8, #0           ' resync if frequency is zero
    ' nop

    ' oscillator 9 (op4)
    '
    add phases+9, freqs+9           ' phase += frequency
    mov r0, phases+9                ' establish working phase in r0
osc9_mod                            ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc9_fb                             ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+9             ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc9_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+9, g_freqs+9 wz    ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+11, r0                ' adjust result negative for bottom quandrants, store in osc output
osc9_sum                            ' patch: sum in source register
    add outs+11, outs+0             ' output += sum input
    if_z mov phases+9, #0          ' resync if frequency is zero
    ' nop

    ' oscillator 10 (op5)
    '
    add phases+10, freqs+10         ' phase += frequency
    mov r0, phases+10               ' establish working phase in r0
osc10_mod                           ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc10_fb                            ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+10            ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc10_w                              ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+10, g_freqs+10 wz  ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+12, r0                ' adjust result negative for bottom quandrants, store in osc output
osc10_sum                           ' patch: sum in source register
    add outs+12, outs+0             ' output += sum input
    if_z mov phases+10, #0          ' resync if frequency is zero
    ' nop

    ' oscillator 11 (op6)
    '
    add phases+11, freqs+11         ' phase += frequency
    mov r0, phases+11               ' establish working phase in r0
osc11_mod                           ' patch: modulation in source register
    mov r1, outs+0                  ' modulation value
osc11_fb                            ' patch: scale by feedback value or fixed
    shl r1, #22                     ' scale modulation
    add r0, r1                      ' working phase += modulation
    test r0, s90 wz                 ' left/right quadrants -> z
    negnz r0, r0 wc                 ' flip per left/right, top/botton quadrants -> c
    and r0, smask                   ' remove sign bit
    rdword r2, g_envs+11            ' read envelope value
    shr r0, #19                     ' scale to word offset in table
osc11_w                             ' patch: sin/triangle wave
    add r0, g_sine                  ' add table
    rdword r0, r0                   ' r0=log(sin(r0)) (4.10 << 1)
    add r0, r2                      ' apply envelope value
    mov r1, r0                      ' save a copy
    rdlong freqs+11, g_freqs+11 wz  ' read frequency value
    and r0, logmask                 ' lookup table offset
    add r0, g_exp                   ' add table
    rdword r0, r0                   ' r0 = exp(r0) (1.n >> int(log_value))
    shr r1, #11                     ' integer part of r1 (shifted extra bit from word offset)
    shr r0, r1                      ' scale according to r1
    negc outs+13, r0                ' adjust result negative for bottom quandrants, store in osc output
osc11_sum                           ' patch: sum in source register
    add outs+13, outs+0             ' output += sum input
    if_z mov phases+11, #0          ' resync if frequency is zero
    ' nop

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
    add in, outs+8
    wrlong in, g_outs               ' send output

    ' 112 * 12 ops = 1344
    ' LFO = 128
    ' misc = 30 (including minimum wait)

    waitpeq lrmask, lrmask

    rdlong lfo_bias, g_lfo_bias     ' update global LFO bias
    ' nop
    jmp #loop

    ' after wait:
    ' 16..31 clocks

    ' TOTAL: 1533
    ' MAX:   1814 (@44.1k) , 1666 (@48k)

' constants
smask       long    $7fff_ffff      ' not the sign bit
lrmask      long    $00_20_00_00    ' DAC load, use to wait one sample
logmask     long    $3ff << 1       ' lookup table offset mask
s90         long    $4000_0000      ' phase counter bit indicating 90 degrees
lfsr_taps   long    $8020_0002      ' x^32+x^22+x^2+1

' global state
lfsr        long    $1f0            ' noise register
lfo_bias    long    $2000_0000      ' LFO bias (initialized to center)
in          res     1               ' master input
phases      res     13              ' 12 operators and an LFO
freqs       res     12              ' 12 operators (LFO reads directly from global)

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
g_outs      res     2               ' oscillator output for audio, LFO

            fit     outs

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

ModTable
WORD    @osc0_mod, @osc6_mod
WORD    @osc1_mod, @osc7_mod
WORD    @osc2_mod, @osc8_mod
WORD    @osc3_mod, @osc9_mod
WORD    @osc4_mod, @osc10_mod
WORD    @osc5_mod, @osc11_mod

SumTable
WORD    @osc0_sum, @osc6_sum
WORD    @osc1_sum, @osc7_sum
WORD    @osc2_sum, @osc8_sum
WORD    @osc3_sum, @osc9_sum
WORD    @osc4_sum, @osc10_sum
WORD    @osc5_sum, @osc11_sum
