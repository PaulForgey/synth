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
    ' global
    Param_Alg
    Param_Fb
    Param_PitchWheelRange
    Param_PitchEG_Bias_Source
    Param_PitchEG_Bias_Scale
    Param_Pitch_L1
    Param_Pitch_R1
    Param_Pitch_L2
    Param_Pitch_R2
    Param_Pitch_L3
    Param_Pitch_R3
    Param_Pitch_L4
    Param_Pitch_R4
    Param_Transpose
    ' per operator
    Param_Level
    Param_Wave
    Param_Pitch_Multiplier          ' WORD
    Param_Pitch_Detune              ' WORD (alias for Pitch_Multiplier)
    Param_Pitch_Fixed
    Param_Velocity
    Param_EG_Bias_Source
    Param_EG_Bias_Scale
    
    Param_L1
    Param_R1
    Param_L2
    Param_R2
    Param_L3
    Param_R3
    Param_L4
    Param_R4
    Param_RateScale
    Param_Breakpoint
    Param_LKeyScale
    Param_RKeyScale
    Param_Curve
    Param_CopyTo
    
    ' per LFO
    Param_LFO_Freq                  ' LONG
    Param_LFO_Level
    Param_LFO_Shape

    Param_Omni
    Param_Channel
    Param_Save                      ' WORD
    Param_Load                      ' WORD

    Param_Max

    Param_First_Global              = Param_Alg
    Param_Last_Global               = Param_Transpose

    Param_First_Operator            = Param_Level
    Param_Last_Operator             = Param_EG_Bias_Scale

    Param_First_Envelope            = Param_L1
    Param_Last_Envelope             = Param_CopyTo

    Param_First_LFO                 = Param_LFO_Freq
    Param_Last_LFO                  = Param_LFO_Shape

    BufferLength                    = 176   ' includes Midi encoding overhead

OBJ
    store       : "synth.patch.data.store"

VAR
    ' following variables are byte copied to or from NV storage as is
    LONG    LFOFreqs_[4]                    ' LFO frequencies
    WORD    PitchMultipliers_[6]            ' pitch "multipliers" (signed value to add in pitch units)
    BYTE    Alg_                            ' algorithm 0-31
    BYTE    Fb_                             ' feedback scaling 0-31
    BYTE    PitchWheelRange_                ' pitch wheel range 0-31
    BYTE    LFOLevels_[4]                   ' LFO output levels, same presentation as level scaling
    BYTE    LFOShapes_[4]                   ' LFO shapes 0-5 (refer to synth.osc for definitions)
    BYTE    Envelopes_[56]                  ' pitch + 6 operator envelopes
    BYTE    EGBiases_[14]                   ' pitch + 6 operator EG bias tuples: source, scale
    BYTE    VelocityScales_[6]              ' velocity scaling 0-7, 0 for no velocity sensitivity
    BYTE    LevelScales_[6]                 ' envelope level scaling, $ff is full, 0 is off
    BYTE    RateScales_[6]                  ' envelope rate scaling, 0 (none) to 31 (extreme)
    BYTE    PitchFixed_                     ' bit array of multiplier/fixed per operator (0=multplier, bit 0=operator 1)
    BYTE    Transpose_                      ' transposition, in signed note steps
    BYTE    Waves_                          ' bit array of sine/triangle per operator (0=sine, bit 0=operator 1)
    BYTE    Breakpoints_[6]                 ' key scale breakpoints
    BYTE    LKeyScales_[6]                  ' left key scale levels
    BYTE    RKeyScales_[6]                  ' right key scale levels
    BYTE    Curves_[6]                      ' key scale curve (bitmap 1..0: right exp(lin),up(down), 3..2: left)
    ' 154 bytes
    BYTE    Pad_[22]                        ' 154 (already divisible by 7) + 8th bit for 22 groups
    ' from here down is not written to NV storage
    BYTE    LabelBuf_[6]
    BYTE    CopyTo_
    BYTE    Channel_
    BYTE    Omni_
 
PUB Init(Pin)
{{
Pin: CS pin assigned to flash
}}
    store.Init(Pin)
    Omni_ := TRUE
    LoadDefault

PUB Buffer
    return @LFOFreqs_
 
PUB LoadDefault | i, j, ptr
{{
Load up a default patch, algorithm 1, single operator 1 for a sine wave, organ shaped envelopes on all operators
}}
    ByteFill(@LFOFreqs_, 0, @LabelBuf_ - @LFOFreqs_)
    PitchWheelRange_ := 13  ' 2 octaves
    ptr := @Envelopes_
    repeat i from 0 to 3
        BYTE[ptr++] := $80
        BYTE[ptr++] := $ff
    repeat i from 0 to 5
        repeat j from 0 to 2
            BYTE[ptr++] := $ff
            BYTE[ptr++] := $ff
        BYTE[ptr++] := 0
        BYTE[ptr++] := $ff
    LevelScales_[0] := $ff
    repeat i from 0 to 3
        LFOFreqs_[i] := 97388   ' ~1 Hz
        LFOLevels_[i] := $ff
    CopyTo_ := 1

PUB ProgramChange(Value)
{{
Handle program change MIDI control message
}}
    PatchNum_ := (PatchNum_ & !$7f) | Value
    Load

PUB Load
{{
Load selected patch number from NV storage
}}
    if not store.Read(PatchNum_, @LFOFreqs_, @LabelBuf_-@LFOFreqs_)
        LoadDefault

PUB Save
{{
Save patch to NV storage at selected patch number
}}
    store.Write(PatchNum_, @LFOFreqs_, @LabelBuf_-@LFOFreqs_)

PUB ParamLabel(p)
{{
Display label for parameter
}}
    ByteMove(@LabelBuf_, @BYTE[@ParamLabels][p*4], 4)
    LabelBuf_[4] := 0
    return @LabelBuf_
'
' accessors for consumption
PUB LFOFreqPtr(l)
{{
Pointer to LFO frequency
l: 0-3
}}
    return @LFOFreqs_[l]

PUB LFOLevel(l)
{{
LFO level
l: 0-3
}}
    return LFOLevels_[l]

PUB LFOShape(n)
{{
LFO shape
n: 0-3
}}
    return LFOShapes_[n]

PUB PitchMultiplier(op)
{{
Pitch "multiplier" for this operator, actually expressed in signed pitch units
Every $400 is one octave for *2 or /2
}}
    return ~~PitchMultipliers_[op]

PUB PitchFixed(op)
{{
Is pitch fixed for this operator?
op: 0-5
}}
    return PitchFixed_ & (1 << op)

PUB Alg
{{
Algorithn, 0-31
}}
    return Alg_

PUB FbPtr
{{
Byte pointer to feedback scale
}}
    return @Fb_

PUB PitchWheelRange
{{
Pitch wheel range
}}
    return PitchWheelRange_

PUB EnvelopeLevel(e, s)
{{
Envelope level for stage
e: 0-6, 0 being the pitch envelope
s: 0-3
}}
    return Envelopes_[e*8 + s*2]
    
PUB EnvelopeRate(e, s)
{{
Envelope rate for stage
e: 0-6, 0 being the pitch envlope
s: 0-3
}}
    return Envelopes_[(e*8 + s*2) + 1]

PUB EGBiasSource(e)
{{
EG bias source for envelope
e: 0-6, 0 being the pitch envelope
}}
    return EGBiases_[e*2]

PUB EGBiasScale(e)
{{
EG bias scale for envelope
e: 0-6, 0 being the pitch envelope
}}
    return EGBiases_[(e*2)+1]

PUB VelocityScale(o)
{{
Velocity scale for operator
o:  0-5
}}
    return VelocityScales_[o]

PUB LevelScale(o)
{{
Level scale for operator
o:  0-5
}}
    return LevelScales_[o]

PUB LKeyScale(o)
{{
Key scale for operator
o:  0-5
}}
    return LKeyScales_[o]

PUB RKeyScale(o)
{{
Kewy scale for operator
o:  0-5
}}
    return RKeyScales_[o]

PUB RateScale(o)
{{
Rate scale for operator
o:  0-5
}}
    return RateScales_[o]

PUB Breakpoint(o)
{{
Breakpoint for operator
o:  0-5
}}
    return Breakpoints_[o]

PUB Curve(o)
{{
Keyscale curve for operator
o:  0-5
returns:
3210
||++ R (two bits same as:)
|--- 1: up 0: down
---- 1: exp 0: lin
}}
    return Curves_[o]

PUB Omni
{{
Are we in MIDI omni mode?
}}
    return Omni_

PUB SetOmni(Value)
{{
Set MIDI omni mode
}}
    Omni_ := Value

PUB Channel
{{
Configured MIDI channel
}}
    return Channel_

PUB CopyTo
{{
Return destination envelope for CopyTo command
}}
    return CopyTo_

PUB Transpose
{{
Signed 8 bit transposition (used to set middle C, usually by octave so divisible by 12)
}}
    return ~Transpose_

PUB Waves
{{
Return operator wave bit array
}}
    return Waves_

PUB PatchNum
    return PatchNum_

PUB CopyEnv(t, f)
{{
Copy envelope sequence f to t
envelope 0 is the pitch envelope. The UI should have no reason to actually copy it.
f: source sequence, 0-6
t: destination sequence, 0-6
}}
    ByteMove(@Envelopes_[t*8], @Envelopes_[f*8], 8)
    if f > 0 and t > 0
        RateScales_[t] := RateScales_[f]
    
PUB ParamPtr(o, l, p)
{{
Return pointer to a value by operator and param number
It is up to the caller to know if the parameter is a BYTE, WORD or LONG value
o: operator 0-5 (ignored for parameters that are not operator specific)
l: LFO 0-3 (ignored for parameters that are not LFO specific)
p: parameter
}}
    case p
        ' per LFO parameters
        Param_LFO_Freq:
            return @LFOFreqs_[l]
    
        Param_LFO_Level:
            return @LFOLevels_[l]

        Param_LFO_Shape:
            return @LFOShapes_[l]

        ' global parameters
        Param_Alg:
            return @Alg_
    
        Param_Fb:
            return @Fb_

        Param_PitchWheelRange:
            return @PitchWheelRange_

        Param_Pitch_L1..Param_Pitch_R4:
            return @Envelopes_[p - Param_Pitch_L1]


        Param_PitchEG_Bias_Source:
            return @EGBiases_[0]

        Param_PitchEG_Bias_Scale:
            return @EGBiases_[1]

        Param_Transpose:
            return @Transpose_

        ' per operator parameters
        Param_Pitch_Fixed:
            return @PitchFixed_

        Param_Pitch_Multiplier, Param_Pitch_Detune:
            return @PitchMultipliers_[o]

        Param_Level:
            return @LevelScales_[o]

        Param_Wave:
            return @Waves_
    
        Param_Velocity:
            return @VelocityScales_[o]

        Param_L1..Param_R4:
            return @Envelopes_[((1+o)*8)+(p-Param_L1)]

        Param_RateScale:
            return @RateScales_[o]

        Param_Breakpoint:
            return @Breakpoints_[o]

        Param_LKeyScale:
            return @LKeyScales_[o]

        Param_RKeyScale:
            return @RKeyScales_[o]

        Param_Curve:
            return @Curves_[o]

        Param_CopyTo:
            return @CopyTo_

        Param_EG_Bias_Source..Param_EG_Bias_Scale:
            return @EGBiases_[(1+o)*2+(p-Param_EG_Bias_Source)]

        Param_Load, Param_Save:
            return @PatchNum_

        Param_Omni:
            return @Omni_
        
        Param_Channel:
            return @Channel_

    abort $10 ' internal error for unhandled parameter

DAT
PatchNum_   WORD    0

ParamLabels
BYTE    "ALG "
BYTE    "FB  "
BYTE    "BEND"
BYTE    "PEBS"
BYTE    "PEBC"
BYTE    "P L1"
BYTE    "P R1"
BYTE    "P L2"
BYTE    "P R2"
BYTE    "P L3"
BYTE    "P R3"
BYTE    "P L4"
BYTE    "P R4"
BYTE    "MIDC"
BYTE    "LVL "
BYTE    "WAVE"
BYTE    "FREQ"
BYTE    "TUNE"
BYTE    "FIX "
BYTE    "VEL "
BYTE    "EBS "
BYTE    "EBC "
BYTE    "L1  "
BYTE    "R1  "
BYTE    "L2  "
BYTE    "R2  "
BYTE    "L3  "
BYTE    "R3  "
BYTE    "L4  "
BYTE    "R4  "
BYTE    "RSCL"
BYTE    "KBRK"
BYTE    "KLSC"
BYTE    "KRSC"
BYTE    "KCUR"
BYTE    "COPY"
BYTE    "FREQ"
BYTE    "LVL "
BYTE    "WAVE"
BYTE    "OMNI"
BYTE    "CHAN"
BYTE    "SAVE"
BYTE    "LOAD"

{{
This module holds all the data for a patch. It is like a document, in that is knows its patch number and how to load and save
itself to non volatile storage. The accessor methods provided allow getting a pointer to a specific numbered parameter as well
as direct access to values that are needed.
}}
