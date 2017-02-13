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
    env[7]      : "synth.env"

VAR
    WORD    OscPitches_
    BYTE    KeyDown_
    BYTE    Sustain_
    BYTE    Tag_

PUB Init(EgPtr, OscPitches, Envs) | i
{{
EgPtr       : base EG pointer for the group of 7 EGs
OscPitches  : array of 6 longs for each operator pitch
Envs        : array of 7*4*2=56 longs defining the 7 envelope sequences
}}
    repeat i from 0 to 6
        env[i].Init(@LONG[EgPtr][i*5], @LONG[Envs][i*8])
    OscPitches_ := OscPitches

PUB Panic | i
{{
Panic the envelope sequences (which in turn panic their EGs)
Also reset KeyDown and Sustain states for all channels
}}
    repeat i from 0 to 6
        env[i].Panic
    KeyDown_ := 0
    Sustain_ := 0

PUB UnTrigger | i
{{
Faster way to accomplish Trigger with all 0 levels
}}
    repeat i from 0 to 6
        env[i].Trigger(0, FALSE, 0)

PUB Trigger(Channel, Pitches, LevelScales, RateScales, NewTag) | i
{{
Channel         : MIDI channel number (only used to track sustain)
Pitches         : array of 6 longs
LevelScales     : array of 7 level scale longs. level 0 indicates key up
RateScales      : array of 7 rate scale words.
NewTag          : tag byte to assign this object instance (for MIDI note being played)
}}
    if LONG[LevelScales][0]
        SetState(Channel, TRUE, @KeyDown_)
        LongMove(OscPitches_, Pitches, 6)
        Tag_ := NewTag | $80
    else
        SetState(Channel, FALSE, @KeyDown_)
        if State(Channel, @Sustain_) or KeyDown_
            return  ' sustain pedal is down or other channels still have us on
        Tag_ &= $7f

    repeat i from 0 to 6
        env[i].Trigger(LONG[LevelScales][i], FALSE, WORD[RateScales][i])

PUB NewNote(PitchLevel, NewTag)
{{
Transition to new note in existing envelope state
PitchLevel      : new LevelScales[0] value
Slide           : do not reset pitch EG value, allowing R1 to act as a portamento
NewTag          : new tag byte to assign this object instance
}}
    Tag_ := NewTag | $80
    env[0].Trigger(PitchLevel, TRUE, 0)

PUB Sustain(Channel, Active)
{{
Update state of sustain pedal
}}
    SetState(Channel, Active, @Sustain_)
    if not (Active or KeyDown_)
        UnTrigger

PUB Tag
{{
Accessor for "tag" value, which is just the MIDI node currently playing
}}
    return Tag_

PUB Untag
    Tag_ := 0

PUB Run | i
{{
Run an iteration of the loop
}}
    repeat i from 0 to 6
        env[i].Run

PRI SetState(Channel, NewState, ptr)
    if NewState
        if Channel < 0
            BYTE[ptr] := $f
        else
            BYTE[ptr] |= (1 << Channel)
    else
        if Channel < 0
            BYTE[ptr] := 0
        else
            BYTE[ptr] &= !(1 << Channel)

PRI State(Channel, ptr)
    result := BYTE[ptr]
    if Channel => 0
        result &= (1 << Channel)

{
This object serves as a controller for an individual voice as requested by the main synth object, and using that object to
accomplish what it does.
}
