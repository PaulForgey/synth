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
    EG_Max  = $3fff_ffff
    EG_Mid  = $2000_0000
    
    #0
    Source_None
    Source_Modulation                   ' do not use with pitch EG
    Source_LFO1
    Source_LFO2
    Source_LFO3
    Source_LFO4
    
    Event_Reload        = %0001
    Event_Silence       = %0010
    Event_MidiConfig    = %0100
    Event_Redraw        = %1000

    #0
    Cmd_None
    Cmd_Load
    Cmd_Save
    Cmd_Dump
    Cmd_Global
    Cmd_Operators
    Cmd_Envelopes
    Cmd_LFOs
    Cmd_CopyTo
    Cmd_Operator
    Cmd_LFO

OBJ
    tables      : "synth.tables"
    algs        : "synth.alg.table"
    data        : "synth.patch.data"    ' model class
    io          : "synth.io"
    display     : "synth.oled"
    si          : "string.integer"

CON
    BufferLength        = data#BufferLength

VAR
    LONG    PitchWheel_                 ' signed, centered at 0
    LONG    ModulationBias_             ' global EG bias, usually from modulation wheel, $2000_0000 <= n < $4000_0000
    LONG    LFOOutputs_[4]              ' LFO output
    LONG    LFOBiases_[4]               ' LFO biases
    LONG    Envelopes_[56]              ' 7 envelopes, each 4 sets of 2 longs (level/rate)
    LONG    RedrawClk_                  ' delayed redraw
    WORD    EGBiases_[14]               ' EG bias source ptr/scale value
    WORD    LFOLevels_[4]               ' LFO levels in unshifted loglevel for, $5800 being silent
    WORD    UILastNote_                 ' hack to adjust note at a time
    BYTE    Events_                     ' Read-and-clear event mask
    BYTE    UIOperator_                 ' operator being edited (0-5)
    BYTE    UILFO_                      ' LFO being edited (0-3)
    BYTE    UIParam_                    ' ui parameter selection
    BYTE    Menu_[3]                    ' what the the three buttons currently do
    BYTE    ValueBuf_[7]                ' buffer to render displayed value

PUB Init(DisplayPin, StorePin) | i
{{
DisplayPin  : CS pin assigned to display
StorePin    : CS pin assigned to flash
}}
    data.Init(StorePin)
    display.Init(DisplayPin)

    repeat i from 0 to 3
        ' we don't do anything with these yet..
        LFOBiases_[i] := $2000_0000     ' centered

    UpdateAll
    SetModulation(0)
    SetPitchWheel($2000)
    ShowSelection
    Events_ |= Event_MidiConfig | Event_Reload

PUB Run | b
{{
Cycle the UI loop
}}
    b := io.Pressed
    if b
        OnButton(b)
    b := io.Turned
    if b
        OnKnob(b)
    if Redraw
        DrawGraph

PUB ProgramChange(Value)
{{
Handle MIDI program change control message
}}
    data.ProgramChange(Value)

PUB LoadFromMidi(s) | sptr, dptr, n
{{
Decode (in place) received SysEx data

s   : TRUE if received valid data, FALSE to otherwise re-load from flash or failing that, default
}}
    if not s
        OnLoad
        return

    sptr := data.Buffer
    dptr := sptr

    repeat CONSTANT(BufferLength / 8)
        n := BYTE[sptr][7]
        repeat 7
            n <<= 1
            BYTE[dptr++] := BYTE[sptr++] | (n & $80)
        sptr++

    Events_ |= (Event_Reload | Event_Silence)
    UpdateAll

PUB Buffer
    return data.Buffer

'
' accessors for engine
' 
PUB LFOOutputPtr(n)
    return @LFOOutputs_[n]

PUB LFOFreqPtr(n)
    return data.LFOFreqPtr(n)

PUB LFOBiasPtr(n)
    return @LFOBiases_[n]

PUB LFOLevelPtr(n)
    return @LFOLevels_[n]

PUB EGBiases
    return @EGBiases_

PUB Envelopes
    return @Envelopes_

PUB Alg
    return data.Alg

PUB LFOShape(n)
    return data.LFOShape(n)

PUB FbPtr
    return data.FbPtr

PUB PitchWheelPtr
    return @PitchWheel_

PUB Omni
    return data.Omni

PUB SetOmni(Value)
    data.SetOmni(Value)

PUB Channel
    return data.Channel

PUB Waves
    return data.Waves

PUB Reload
{{
Read self clearing event state needing oscillator reload
}}
    result := Events_ & Event_Reload
    Events_ &= !Event_Reload

PUB Silence
{{
Read self clearing event state needing to panic the EGs
}}
    result := Events_ & Event_Silence
    Events_ &= !Event_Silence

PUB MidiConfig
{{
Read self clearing event state indicating the list of MIDI channels has changed
}}
    result := Events_ & Event_MidiConfig
    Events_ &= !Event_MidiConfig

PRI Redraw | n
    n := CNT
    if RedrawClk_ and (RedrawClk_ - n) > 0
        result := 0
    else
        RedrawClk_ := n + (CLKFREQ >> 2)
        result := Events_ & Event_Redraw
        Events_ &= !Event_Redraw

'
' interface patch data to native

PRI UpdateEnv | e, s
{{
Update working envelope definitions from patch values
}}
    repeat e from 0 to 6
        repeat s from 0 to 3
            SetEnv(e, s, data.EnvelopeLevel(e, s), data.EnvelopeRate(e, s))
        SetEGBias(e, data.EGBiasSource(e), data.EGBiasScale(e))

PRI Exp(n, b)
{{
exp2 of 5.11 value
b:  result is x.(16-b). e.g. 16 returns an integer, 1 returns a 16.16
}}
    result := WORD[$d000][n & $7ff] | $1_0000
    n ~>= 11
    if n > b
        result <<= (n-b)
    else
        result >>= (b-n)
 
PRI SetEnv(Env, Stage, Level, Rate) | ptr
{{
Env         : envelope 0-6 (0 being pitch, 1-6 operators)
Stage       : stage, 0-3
Level       : 8-bit UI level
Rate        : 8-bit UI rate
}}
    ptr := @Envelopes_[(Env<<3)+(Stage<<1)]

    ' convert UI level to EG
    if Env
        Level := ( (Level << 2) | ((Level & $c0) >> 6) ) << 20
    else
        ' scale the pitch EG a litle differently. $80 is midpoint, of course
        Level := ( (($80 - Level) * $18) + $4000 ) << 15 ' +/- 3 octaves

    ' convert UI rate to EG
    Rate := Exp((Rate + 1) * 240, 16) - 1   ' $ff -> 30 << 11

    LONG[ptr][0] := Level
    LONG[ptr][1] := Rate

PRI SetEGBias(Env, Source, Scale) | ptr, sptr
{{
Env         : envelope 0-6 (0 being pitch, 1-6 operators)
Source      : Source_ constant (do not use Modulation with envelope 0)
Scale       : scale factor 0-31, higher being less influence
}}
    case Source
        Source_None:
            if Env == 0
                sptr := @Mid
            else
                sptr := @Zero
        Source_Modulation:
            sptr := @ModulationBias_
        other:
            sptr := @LFOOutputs_[Source-Source_LFO1]
            
    ptr := @EGBiases_[Env * 2]
    WORD[ptr][0] := sptr
    WORD[ptr][1] := Scale

PRI UpdateLFO | i
    repeat i from 0 to 3
        SetLFOLevel(i, data.LFOLevel(i))

PRI SetLFOLevel(LFO, Level)
    Level := (Level << 2) | ((Level & $c0) >> 6) ' 8 -> 10 bit
    LFOLevels_[LFO] := WORD[tables.EgLogPtr][Level]

' MIDI events (handling or helping to handle)
'
PUB SetPitchWheel(Value)
{{
Value       : MIDI pitch bend value, 0-$3fff, centered at $2000
}}
    PitchWheel_ := ( -(Value - $2000) ) << data.PitchWheelRange

PUB SetModulation(Value)
{{
Value       : MIDI controller value, 0-$7f
}}
    ModulationBias_ := EG_Mid | (($7f - Value) << 22)

PUB Pitches(Note, PitchesPtr) | i, p
{{
Note        : MIDI note value 00-$7f
PitchesPtr  : array of 6 longs to receive pitch unit values
}}
    Note += data.Transpose
    p := WORD[tables.ScalePtr][Note // 12]
    p |= ((Note / 12) + 21) << 10
    
    repeat i from 0 to 5
        if data.PitchFixed(i)
            LONG[PitchesPtr][i] := !(data.PitchMultiplier(i) << 15)
        else
            p += data.PitchMultiplier(i)
            LONG[PitchesPtr][i] := !( (0 #> p <# $7fff) << 15 )

PUB RateScales(Note, RateScalesPtr) | i,  j
{{
Note            : MIDI note value 00-$7f
RateScalesPtr   : array of 7 words to receive rate scale values
}}
    WORD[RateScalesPtr][0] := 0
    repeat i from 1 to 6
        WORD[RateScalesPtr][i] := Exp(data.RateScale(i-1) * Note * 15, 16)

PUB LevelScales(Velocity, LevelScalesPtr) | i, ptr, v, l
{{
Velocity        : MIDI velocity value 00-$7f, 0 for key up
LevelScalesPtr  : array of 7 words to receive level scale values
}}
    if Velocity
        ptr := LevelScalesPtr
        WORD[ptr] := $400 ' never level scale the pitch EG!
        repeat i from 0 to 5
            ptr += 2
            ' velocity sensitivity is actually floor value, and possibly a cheesy way to handle this
            v := ( Velocity #> ($7f >> data.VelocityScale(i)) ) + 1
            ' apply 8 bit level setting slightly non-linearly, then scale against 7 bit velocity
            l := data.LevelScale(i)
            l <<= ( ((l & $c0) >> 6) - 1 ) #> 0
            
            WORD[ptr] := (l * v) >> 7
    else
        repeat i from 0 to 6
            WORD[LevelScalesPtr][i] := 0

'
' UI
PRI OnButton(b)
    case Menu_[b-1]
        Cmd_Load:
            OnLoad
        Cmd_Save:
            OnSave
        Cmd_Dump:
            OnDump
        Cmd_CopyTo:
            OnCopyTo
        Cmd_Operator:
            OnNextOperator
        Cmd_LFO:
            OnNextLFO
        Cmd_Operators:
            OnOperators
        Cmd_Envelopes:
            OnEnvelopes
        Cmd_LFOs:
            OnLFOs
        Cmd_Global:
            OnGlobal
        Cmd_None:

PRI OnKnob(b)
    case b
        1:
            SetSelection(io.Knob(1))
        2..3:
            SetValue(io.Value)
 
PRI SetSelection(s)
    repeat while s < 0
        s += data#Param_Max
    s //= data#Param_Max
    UIParam_ := s
    io.SetKnob(1, s)
    ShowSelection
    Events_ |= Event_Redraw

PRI OnLoad
    data.Load
    Events_ |= (Event_Reload | Event_Silence)
    UpdateAll

PRI UpdateAll
    UpdateEnv
    UpdateLFO
    Events_ |= Event_Redraw

PRI OnSave
    data.Save

PRI OnDump | ptr, n, b
    if UIParam_ == data#Param_Load
        OnLoad
    io.DebugStr(STRING("# PATCH DATA "))
    io.DebugStr(si.Dec(data.PatchNum))
    io.DebugChar(13)
    io.DebugStr(STRING("F0 70 7F 7F "))
    ptr := data.Buffer
    repeat CONSTANT(BufferLength / 8)
        ' BufferLength is in groups of 8 for midi format
        ' Actual data is in that many groups of 7
        n := 0
        repeat 7
            b := BYTE[ptr++]
            n <<= 1
            n |= (b & $80) >> 7
            io.DebugStr(si.Hex(b & $7f, 2))
            io.DebugChar(" ")
        io.DebugStr(si.Hex(n, 2))
        io.DebugChar(13)
    io.DebugStr(STRING("F7", 13))

PRI OnCopyTo
    data.CopyEnv(data.CopyTo, UIOperator_+1)
    UpdateEnv

PRI OnGlobal
    SetSelection(data#Param_First_Global)

PRI OnOperators
    SetSelection(data#Param_First_Operator)

PRI OnEnvelopes
    SetSelection(data#Param_First_Envelope)

PRI OnLFOs
    SetSelection(data#Param_First_LFO)

PRI SetValue(v) | ptr
    ptr := data.ParamPtr(UIOperator_, UILFO_, UIParam_)

    case UIParam_
        data#Param_Alg:
            AdjustByte(ptr, v, 0, 31)
            Events_ |= Event_Reload
        data#Param_Fb, data#Param_PitchWheelRange:
            AdjustByte(ptr, v, 0, 31)
        data#Param_Pitch_L1..data#Param_Pitch_R4, data#Param_L1..data#Param_R4:
            AdjustByte(ptr, v, 0, $ff)
            UpdateEnv
        data#Param_Transpose:
            AdjustByte(ptr, v, -$80, $7f)
        data#Param_RateScale:
            AdjustByte(ptr, v, 0, 16)
        data#Param_PitchEG_Bias_Source, data#Param_EG_Bias_Source:
            AdjustByte(ptr, v, 0, Source_LFO4)
            UpdateEnv
        data#Param_PitchEG_Bias_Scale, data#Param_EG_Bias_Scale:
            AdjustByte(ptr, v, 0, 30)
            UpdateEnv
        data#Param_CopyTo:
            AdjustByte(ptr, v, 1, 6)
        data#Param_Pitch_Multiplier:
            AdjustNote(ptr, v)
        data#Param_Pitch_Fixed:
            AdjustByte(ptr, v, 0, $1)
        data#Param_Pitch_Detune:
            AdjustWord(ptr, v, -$8000, $7fff)
        data#Param_Velocity:
            AdjustByte(ptr, v, 0, 7)
        data#Param_Level:
            AdjustByte(ptr, v, 0, $ff)
        data#Param_Wave:
            AdjustWave(ptr, v)
            Events_ |= Event_Reload
        data#Param_LFO_Freq:
            AdjustLFOFreq(ptr, v)
        data#Param_LFO_Level:
            AdjustByte(ptr, v, 0, $ff)
            UpdateLFO
        data#Param_LFO_Shape:
            AdjustByte(ptr, v, 0, 5)
            Events_ |= Event_Reload
        data#Param_Load, data#Param_Save:
            AdjustWord(ptr, v, 0, $3fff)
        data#Param_Pitch_Fixed:
            AdjustByte(ptr, v, 0, $1)
        data#Param_Omni:
            AdjustByte(ptr, v, 0, $1)
            Events_ |= Event_MidiConfig
        data#Param_Channel:
            AdjustByte(ptr, v, 0, $f)
            Events_ |= Event_MidiConfig
    ShowValue

PRI AdjustWave(ptr, v)
    if v
        BYTE[ptr] |= (1 << UIOperator_)
    else
        BYTE[ptr] &= !(1 << UIOperator_)

PRI AdjustLFOFreq(ptr, value)
    LONG[ptr] := (0 #> value) * 973

PRI AdjustNote(ptr, value) | p, n, i, d
    d := value - ~~UILastNote_
    if ||d => 1024
        AdjustOctave(ptr, d)
        return

    p := ~~WORD[ptr]
    n := ApproxNote(p, 0)
    i := WORD[tables.ScalePtr][n]
    if d > 0 and n == 11
        i -= 1024
        n := 0
    elseif d < 0 and n == 0
        i += 1024
        n := 11
    elseif d > 0
        n++
    else
        n--
    p += (WORD[tables.ScalePtr][n] - i)
    WORD[ptr] := p

PRI AdjustOctave(ptr, d) | p
    p := WORD[ptr]
    if d > 0
        p += 1024
    else
        p -= 1024    
    WORD[ptr] := p

PRI AdjustByte(p, value, lo, hi)
    BYTE[p] := lo #> value <# hi

PRI AdjustWord(p, value, lo, hi)
    WORD[p] := lo #> value <# hi

PRI OnNextOperator
    UIOperator_ := (UIOperator_ + 1) // 6
    ShowSelection

PRI OnNextLFO
    UILFO_ := (UILFO_ + 1) & 3
    ShowSelection

PRI ShowSelection
    ' populate operator/lfo status and set knob color
    case UIParam_
        data#Param_First_Operator..data#Param_Last_Envelope:
            io.SetColor(UIOperator_+1)
            ByteMove(@ValueBuf_, STRING("OP  "), 4)
            ValueBuf_[4] := "1" + UIOperator_
        data#Param_First_LFO..data#Param_Last_LFO:
            io.SetColor(UILFO_+1)
            ByteMove(@ValueBuf_, STRING("LFO "), 4)
            ValueBuf_[4] := "1" + UILFO_
        other:
            io.SetColor(7)
            ByteFill(@ValueBuf_, " ", 5)
    ValueBuf_[5] := 0
    display.Write(0, 0, @ValueBuf_)

    ' populate param label value value
    display.Write(2, 0, data.ParamLabel(UIParam_))
    ShowValue
    
    ' populate the button labels
    case UIParam_
        data#Param_Load:
            SetButtons(Cmd_Dump, Cmd_None, Cmd_Load)
        data#Param_Save:
            SetButtons(Cmd_Dump, Cmd_Save, Cmd_None)
        data#Param_CopyTo:
            SetButtons(Cmd_Operator, Cmd_CopyTo, Cmd_None)
        data#Param_First_Global..data#Param_Last_Global:
            SetButtons(Cmd_None, Cmd_None, Cmd_Operators)
        data#Param_First_Operator..data#Param_Last_Operator:
            SetButtons(Cmd_Operator, Cmd_Global, Cmd_Envelopes)
        data#Param_First_Envelope..data#Param_Last_Envelope:
            SetButtons(Cmd_Operator, Cmd_Operators, Cmd_LFOs)
        data#Param_First_LFO..data#Param_Last_LFO:
            SetButtons(Cmd_LFO, Cmd_Envelopes, Cmd_None)

PRI SetButtons(cmd1, cmd2, cmd3)
    SetButton(1, cmd1)
    SetButton(2, cmd2)
    SetButton(3, cmd3)

PRI SetButton(b, cmd)
    Menu_[b-1] := cmd
    ValueBuf_[3] := 0
    ByteMove(@ValueBuf_, @BYTE[@CmdLabels][cmd*3], 3)
    display.Write(3, (b-1)*8, @ValueBuf_)

PRI ShowValue | ptr, v, c
    c := $10
    ptr := data.ParamPtr(UIOperator_, UILFO_, UIParam_)
    ByteFill(@ValueBuf_, " ", 6)
    ValueBuf_[6] := 0
    case UIParam_
        data#Param_Alg:
            v := ShowAlg(ptr, @c)
        data#Param_Pitch_Fixed, data#Param_Omni:
            v := ShowBool(ptr)
        data#Param_Pitch_Multiplier:
            v := ShowPitch(ptr, @c)
            UILastNote_ := v
        data#Param_Pitch_Detune:
            v := ShowDetune(ptr)
        data#Param_PitchEG_Bias_Source, data#Param_EG_Bias_Source:
            v := ShowBiasSource(ptr)
        data#Param_Transpose:
            v := ShowTranspose(ptr, @c)
        data#Param_LFO_Freq:
            v := ShowLFOFreq(ptr, @c)
        data#Param_LFO_Shape:
            v := ShowLFOShape(ptr)
        data#Param_Load, data#Param_Save:
            v := ShowPatch(ptr, @c)
        data#Param_Pitch_L1..data#Param_Pitch_R4:
            v := ShowEnv(ptr, 0)
        data#Param_L1..data#Param_R4:
            v := ShowEnv(ptr, UIOperator_+1)
        data#Param_Wave:
            v := ShowWave(ptr, UIOperator_)
        other:
            v := ShowByte(ptr)
    display.Write(2, 10, @ValueBuf_)
    io.SetValue(v, c)

PRI ShowWave(ptr, o)
    result := (BYTE[ptr] >> o) & 1
    ShowWaveform(result)

PRI ShowEnv(ptr, e)
    result := ShowByte(ptr)
    Events_ |= Event_Redraw

PRI ShowAlg(ptr, cptr)
    LONG[cptr] := 1
    result := BYTE[ptr]
    ByteMove(@ValueBuf_, si.DecPadded(result+1, 2), 2)
    Events_ |= Event_Redraw

PRI ShowTranspose(ptr, cptr) | n
    LONG[cptr] := 12
    result := ~BYTE[ptr]
    
    ' frame offset of 0 as middle C being C-5
    n := result + 60
    ByteMove(@ValueBuf_, @BYTE[@Notes][(n//12)*2], 2)
    ByteMove(@ValueBuf_[2], si.DecPadded(n/12, 3), 3)

PRI ShowBool(ptr)
    if BYTE[ptr]
        result := 1
        ValueBuf_[5] := "Y"
    else
        result := 0
        ValueBuf_[5] := "N"

PRI ShowPitch(ptr, cptr)
    LONG[cptr] := $400
    if data.PitchFixed(UIOperator_)
        result := ShowPitchAsNote(ptr)
    else
        result := ShowPitchAsMultiplier(ptr)

PRI ShowPitchAsMultiplier(ptr) | x, y
    result := ~~WORD[ptr]
    x := Exp(result << 1, 0)
    y := ((x & $ffff) * 100) >> 16
    ValueBuf_[0] := "X"
    ByteMove(@ValueBuf_[1], si.DecPadded(x >> 16, 2), 2)
    ValueBuf_[3] := "."
    ByteMove(@ValueBuf_[4], si.DecPadded(y, 2), 2)

PRI ApproxNote(n, ptr)
{{
return note index for the pitch units, and optionally a signed difference
}}
    n &= $3ff
    if n => 982 ' more than halfway to C in next octave, so call this detuned below C
        n -= 1024
        result := 0
    else
        repeat result from 0 to 10
            if n =< WORD[tables.ScalePtr][result] + 42
                quit
    if ptr
        LONG[ptr] := n - WORD[tables.ScalePtr][result]

PRI ShowPitchAsNote(ptr) | o, p, i
    result := WORD[ptr]
    p := result
    o := p >> 10
    i := ApproxNote(p, 0)
    ByteMove(@ValueBuf_, @BYTE[@Notes][i*2], 2)
    o -= 21
    ByteMove(@ValueBuf_[2], si.DecPadded(o, 3), 3)

PRI ShowDetune(ptr) | units
    result := ~~WORD[ptr]
    ApproxNote(result, @units)
    ByteMove(@ValueBuf_, si.DecPadded(units, 6), 6)

PRI ShowBiasSource(ptr)
    result := BYTE[ptr]
    case result
        Source_None:
            ByteMove(@ValueBuf_, STRING("OFF"), 3)
        Source_Modulation:
            ByteMove(@ValueBuf_, STRING("MOD"), 3)
        Source_LFO1..Source_LFO4:
            ByteMove(@ValueBuf_, STRING("LFO"), 3)
            ValueBuf_[3] := "1" + (result - Source_LFO1)

PRI ShowLFOFreq(ptr, cptr)
    LONG[cptr] := 100
    result := LONG[ptr] / 973

    ByteMove(@ValueBuf_, si.DecPadded(result, 6), 6)

PRI ShowLFOShape(ptr)
    result := BYTE[ptr]
    ShowWaveform(result)

PRI ShowWaveform(w)
    case w
        0: ' sine
            ByteMove(@ValueBuf_, STRING(1,2,3,4,1,2), 6)
        1: ' triangle
            ByteMove(@ValueBuf_, STRING(5,6,7,8,5,6), 6)
        2: ' saw up
            ByteMove(@ValueBuf_, STRING(5,9,5,9,5,9), 6)
        3: ' saw down
            ByteMove(@ValueBuf_, STRING(7,10,7,10,7,10), 6)
        4: ' square
            ByteMove(@ValueBuf_, STRING(11,12,13,14,11,12), 6)
        5: ' noise
            ByteMove(@ValueBuf_, STRING("S & H"), 5)

PRI ShowPatch(ptr, cptr)
    LONG[cptr] := $80
    return ShowWord(ptr)

PRI ShowWord(ptr)
    result := WORD[ptr]
    ByteMove(@ValueBuf_, si.Hex(result, 4), 4)

PRI ShowByte(ptr)
    result := BYTE[ptr]
    ByteMove(@ValueBuf_, si.Hex(result, 2), 2)

PRI DrawOp(x, y, o, ops) | mod, sum, fb, n
    n := BYTE[ops][o]
    mod := n & 7
    sum := (n >> 4) & 7
    fb := n & $88

    ' decorate the FB op
    if fb
        display.Put(3-y, 25+x, "-")    
        if n & $80
            mod := 0

    display.Put(3-y, 24+x, "1"+o)
    if mod
        x := DrawOp(x, y+1, mod-1, ops)
    if sum
        x := DrawOp(x+3, y, sum-1, ops)
    return x

PRI ClearGraph | row
    display.Clear(66, 0, 131, 3)

PRI DrawAlg | ops, row
    ops := @BYTE[algs.AlgTablePtr][data.Alg * 6]
    DrawOp(0, 0, 0, ops)

PRI DrawEnv(e) | s
    ValueBuf_[2] := 0
    display.Write(0, 28, STRING("LEVEL"))
    display.Write(3, 29, STRING("RATE"))
    repeat s from 0 to 3
        ByteMove(@ValueBuf_, si.Hex(data.EnvelopeLevel(e, s), 2), 2)
        display.Write(1, 23+s*5, @ValueBuf_)
        ByteMove(@ValueBuf_, si.Hex(data.EnvelopeRate(e, s), 2), 2)
        display.Write(2, 23+s*5, @ValueBuf_)

PRI DrawGraph
    ClearGraph
    case UIParam_
        data#Param_Pitch_L1..data#Param_Pitch_R4:
            DrawEnv(0)
        data#Param_L1..data#Param_R4:
            DrawEnv(UIOperator_+1)
        data#Param_Alg, data#Param_First_Operator..data#Param_Last_Operator:
            DrawAlg

DAT
' constants to point at
Zero    LONG    0
Mid     LONG    $2000_0000

Notes
BYTE    " C"
BYTE    "C#"
BYTE    " D"
BYTE    "D#"
BYTE    " E"
BYTE    " F"
BYTE    "F#"
BYTE    " G"
BYTE    "G#"
BYTE    " A"
BYTE    "A#"
BYTE    " B"

CmdLabels
BYTE    "   "
BYTE    "LOD"
BYTE    "SAV"
BYTE    "DMP"
BYTE    "GBL"
BYTE    "OPS"
BYTE    "ENV"
BYTE    "LFO"
BYTE    "CPY"
BYTE    "OP "
BYTE    "LFO"

{{
This object serves as a controller class between the model class synth.path.data and view classes synth.io and synth.oled
To the main synth class, it also serves as a model class
}}
