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
    _clkmode  = xtal1 + pll8x
    _xinfreq = 10_000_000

    Pin_DIN             = 0
    Pin_CLK             = 1
    Pin_AD              = 2
    Pin_DAC             = 3
    Pin_Display         = 4
    Pin_Store           = 5
    Pin_RST             = 6
    Pin_Buttons         = 7 '..15
    Pin_MIDI            = 16
    Pin_DACDAT          = 20
    Pin_DACLRC          = 21
    Pin_BCLK            = 22
    Pin_DACCLK          = 23
    Pin_DOUT            = 24
    Pin_Debug           = 30

    ' midi control messages we care about (channel bits 0)
    ' channel voice
    MIDI_NoteOff        = $80
    MIDI_NoteOn         = $90
    MIDI_ControlChange  = $b0
    MIDI_ProgramChange  = $c0
    MIDI_PitchBend      = $e0
    MIDI_SysEx          = $f0
    MIDI_EndSysEx       = $f7
    
    ' midi controller assigments
    ' XXX supporting data entry would be nice
    MIDI_C_Modulation   = 1
    MIDI_C_Sustain      = 64
    MIDI_C_Panic        = 120
    MIDI_C_AllOff       = 123
    MIDI_C_OmniOff      = 124
    MIDI_C_OmniOn       = 125
    MIDI_C_Mono         = 126
    MIDI_C_Poly         = 127

OBJ
    io          : "synth.io"
    si          : "string.integer"
    osc[4]      : "synth.osc"
    eg[2]       : "synth.eg"
    voice[8]    : "synth.voice"
    patch       : "synth.patch"

    tables      : "synth.tables"

VAR
    LONG    Pitches_[6]             ' parameter from patch -> voice (not persistent)
    WORD    LevelScales_[7]         ' parameter from patch -> voice (not persistent)
    WORD    RateScales_[7]          ' parameter from patch -> voice (not persistent)
    WORD    Freqs_[13*4]            ' 12 operators, 1 LFO per bank * 4 (oriented for osc object)
    WORD    EGs_[13*4]              ' 12 operators, 1 LFO per bank * 4 (oriented for osc object)
    LONG    Audio_[4]               ' audio output pointers * 4
    BYTE    MidiControl_            ' current MIDI control message, or 0 if waiting
    BYTE    NextVoice_              ' round robin voice assigment
    BYTE    RunVoice_               ' round robin voice idle tasking

PUB Boot | err
    io.Start(Pin_Buttons, Pin_MIDI, Pin_Debug)
    ' start the core I/O module
    err := \Main
    io.DebugStr(STRING(13, 13, "** ABORT:"))
    io.DebugStr(si.Hex(err, 8))
    io.DebugChar(13)
    repeat

PRI Main | n
    io.DebugStr(STRING(13, 13, "== Main", 13))
    Init
    io.DebugStr(STRING("Initialized", 13))
    
    repeat
        MidiLoop
        OscLoop
        patch.Run ' UI loop

PRI Init | i, j, e
    ' start the fron panel
    patch.Init(Pin_Display, Pin_Store)

    ' start the EGs
    eg[0].InitDAC(Pin_DAC, Pin_DACCLK)
    eg[0].Start(patch.PitchWheelPtr, patch.EgBiases, @Audio_[3])
    eg[1].Start(patch.PitchWheelPtr, patch.EgBiases, 0)

    ' point everything
    ' the gymnastics are easier if we think in terms of oscillator banks
    repeat i from 0 to 3
        ' two voices here, 6 operators each
        e := (i & 1) * 14
        repeat j from 0 to 5
            ' eg objects' entries are arranged, per voice, as pitch, op1-6 (groups of 7)
            ' osc objects' entries are arranged, per bank, as op1-12, LFO
            EGs_[i*13+j]     := eg[i>>1].EgPtr(e+j+1, eg#EG_LogLevel)
            EGs_[i*13+j+6]   := eg[i>>1].EgPtr(e+j+8, eg#EG_LogLevel)
            Freqs_[i*13+j]   := eg[i>>1].EgPtr(e+j+1, eg#EG_Freq)
            Freqs_[i*13+j+6] := eg[i>>1].EgPtr(e+j+8, eg#EG_Freq)
        EGs_[i*13+12]   := patch.LFOLevelPtr(i)
        Freqs_[i*13+12] := patch.LFOFreqPtr(i)

    ' init the voices
    repeat i from 0 to 7
        ' each voice uses a set of 7 EGs (pitch, op1-6)
        ' 8 voices share 2 EG cores, with each EG core providing 4 sets of 7 EGs
        voice[i].Init(eg[i>>2].EgPtr((i&3)*7,0), eg[i>>2].OscPitches(i&3), patch.Envelopes)

PRI RestartOsc | i, ptr
    ptr := @Zero
    repeat i from 0 to 3
        osc[i].Start(@Freqs_[i*13], @EGs_[i*13], patch.FbPtr, patch.LFOBiasPtr(i), ptr, @Audio_[i], patch.LFOOutputPtr(i), patch.LFOShape(i), patch.Waves, patch.Alg)
        ptr := @Audio_[i]

PRI MidiControl
    if not MidiControl_
        MidiControl_ := io.RecvMidiControl
    return MidiControl_

PRI MidiData(Ptr, Size)
    result := io.RecvMidiData(Ptr, Size)
    if result
        MidiControl_ := 0

' top level MIDI parsing
PRI MidiLoop
    if patch.MidiConfig
        io.RemoveAllChannels
        if patch.Omni
            io.AddAllChannels
        else
            io.AddChannel(patch.Channel)

    repeat while MidiControl
        case MidiControl & $f0
            MIDI_NoteOff:
                OnMidiNoteOff
            MIDI_NoteOn:
                OnMidiNoteOn
            MIDI_ControlChange:
                OnMidiControlChange
            MIDI_ProgramChange:
                OnMidiProgramChange
            MIDI_PitchBend:
                OnMidiPitchBend
            other:  ' system common
                case MidiControl
                    MIDI_SysEx:
                        OnMidiSysEx
                    other:
                        MidiControl_ := 0

PRI OnMidiNoteOff | d
    d := 0
    if MidiData(@d, 2)
        OnNote(d & $7f, 0)    

PRI OnMidiNoteOn | d
    d := 0
    if MidiData(@d, 2)
        OnNote(d & $7f, d >> 8)

PRI OnMidiControlChange | d, c
    d := 0
    if MidiData(@d, 2)
        c := d & $7f
        d >>= 8
        case c
            MIDI_C_Sustain:
                OnSustain(d > 63)
            MIDI_C_Modulation:
                OnModulation(d)
            MIDI_C_Panic:
                Panic
            MIDI_C_AllOff:
                AllOff
            MIDI_C_OmniOff:
                OnOmni(FALSE)
            MIDI_C_OmniOn:
                OnOmni(TRUE)
            MIDI_C_Mono:
                OnMono(d)
            MIDI_C_Poly:
                OnPoly

PRI OnMidiProgramChange | d
    d := 0
    if MidiData(@d, 1)
        OnProgramChange(d)

PRI OnMidiPitchBend | d
    d := 0
    if MidiData(@d, 2)
        OnPitchBend((d & $7f) | ((d >> 1) & $3f80))

PRI OnMidiSysEx | d
    d := 0
    ' be a bastard and use $70, $7f, $7f as our three byte ID hoping it doesn't stample someone
    if MidiData(@d, 3) and d == $7f7f70
        result := io.RecvMidiBulk(patch.Buffer, patch#BufferLength)
        patch.LoadFromMidi(result)

' parsed MIDI event handling
PRI OnSustain(Active) | v
    repeat v from 0 to 7
        voice[v].Sustain(Active)

PRI AllOff | v
    repeat v from 0 to 7
        voice[v].Sustain(FALSE)
        voice[v].UnTrigger

PRI OnModulation(Value)
    patch.SetModulation(Value)

PRI OnNote(Note, Velocity) | v
    repeat v from 0 to 7
        ' use same voice for same note
        if voice[v].Tag & $7f == Note
            quit
    if v > 7
        ' no current/last voice for this note, so round-robbin assign one
        if not Velocity
            return ' note up on not-playing (likely exceeded polyphonic limit)
        repeat 8
            v := NextVoice_
            NextVoice_ := (NextVoice_+1) & $7
            if not (voice[v].Tag & $80) ' only take over a key down voice as a last resort
                quit

    patch.Pitches(Note, @Pitches_)
    patch.LevelScales(Velocity, Note, @LevelScales_)
    patch.RateScales(Note, @RateScales_)
    voice[v].Trigger(@Pitches_, @LevelScales_, @RateScales_, Note)

PRI OnPitchBend(Value)
    patch.SetPitchWheel(Value)

PRI OnProgramChange(Value)
    patch.ProgramChange(Value)

PRI OnOmni(Value)
    patch.SetOmni(Value)
    AllOff

PRI OnMono(Channels)
    ' TODO mono mode (although not multitimbral)
    if Channels == 0
        patch.SetOmni(TRUE)
    AllOff

PRI OnPoly
    ' TODO turn off mono mode
    AllOff

PRI OscLoop | i
    if patch.Silence
        Panic
        io.DebugStr(STRING("Panic", 13))
    if patch.Reload
        RestartOsc        
        io.DebugStr(STRING("RestartOsc", 13))
    voice[RunVoice_].Run
    RunVoice_ := (RunVoice_+1) & $7

PRI Panic | v
    repeat v from 0 to 7
        voice[v].Panic

DAT
Zero    LONG    0

{{
This object serves as the main controller object for the synth.
View objects: synth.osc, synth.eg
Model objects: synth.patch
synth.voice is a 1:many controller relationship with this object

Overview of the moving audio parts, from perspective of one voice instance (there are actually 8 voices)

. <-- --> : data flow
. &       : indirection; reads or write data elsewhere
. &*	  : indirection within self; data is routed with same instance via controller storage

/============/
| Operators  |
|            |
| &freq      | <-- EGs
| &eg        | <-- EGs
| &*mod      |
| &*in       |
| &*out      | --> DAC
| shape      | <-- Patch
| algorithm  | <-- Patch
/============/

/============/
| LFOs       |
|            |
| &freq      | <-- Patch
| &eg        | <-- Patch
| &bias      | <-- Patch
| shape      | <-- Patch
| &out       | --> Patch
/============/

/============/
| EGs        |
|            |
| freq       | --> Operators
| eg         | --> Operators
| pitch      | <-- Voice
| rate       | <-- Envelope
| goal       | <-- Envelope
| level      | <-> Envelope
| &bias      | <-- Patch (routes either LFO or modulation)
| bias_scale | <-- Patch
/============/

/============/
| Envelopes  |
|            |
| levels     | <-- Patch
| rates      | <-- Patch
| stage      | <-- Voice
| &level     | <-> EGs
| &rate      | --> EGs
| &goal      | --> EGs
/============/

+------------+
| Voice      |
|            |
| stage      | --> Envelopes
| pitch      | --> EGs
| lfo_out    | <-- LFOs --> EGs
| modulation | --> EGs
+------------+

}}
