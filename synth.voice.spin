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
    KeyDown     = %01
    PedalDown   = %10

OBJ
    env[7]      : "synth.env"

VAR
    LONG    KeysDown_[4]
    WORD    OscPitches_
    BYTE    State_
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
    State_ := 0
    Tag_ := 0

PUB UnTrigger | i
{{
Faster way to accomplish Trigger with all 0 levels
}}
    repeat i from 0 to 6
        env[i].Trigger(0, FALSE, 0)

PUB Trigger(Pitches, LevelScales, RateScales, NewTag) | i, reset
{{
Pitches         : array of 6 longs
LevelScales     : array of 7 level scale longs. level 0 indicates key up
RateScales      : array of 7 rate scale words.
NewTag          : tag byte to assign this object instance (for MIDI note being played)
}}
    reset := FALSE
    if LONG[LevelScales][0]
        if Tag_ & $7f <> NewTag
            reset := TRUE
        SetKey(TRUE)
        Tag_ := NewTag | $80
        LongMove(OscPitches_, Pitches, 6)
    else
        SetKey(FALSE)
        Tag_ &= $7f
        if State_
            return  ' sustain pedal is down

    repeat i from 0 to 6
        env[i].Trigger(LONG[LevelScales][i], reset, WORD[RateScales][i])

PUB NewNote(PitchLevel, NewTag)
{{
Transition to new note in existing envelope state
PitchLevel      : new LevelScales[0] value
NewTag          : new tag byte to assign this object instance
}}
    Tag_ := NewTag | $80
    env[0].Trigger(PitchLevel, FALSE, 0)

PUB Sustain(Active)
{{
Update state of sustain pedal
}}
    SetPedal(Active)
    if State_ == 0
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

PUB MonoNote(Note, Down) | i
{{
Return:
    Note if no other keys are down, else <> Note
}}
    if not Down
        KeysDown_[Note >> 5] &= !(1 << (Note & $1f))
        repeat i from 3 to 0
            result := >|KeysDown_[i]
            if result
                result += (i << 5)
                quit
        if result
            result--
        else
            result := Note
    else
        KeysDown_[Note >> 5] |= (1 << (Note & $1f))
        if State_ & KeyDown
            result := -1
        else
            result := Note

PRI SetKey(Down)
    if Down
        State_ |= KeyDown
    else
        State_ &= CONSTANT(!KeyDown)

PRI SetPedal(Down)
    if Down
        State_ |= PedalDown
    else
        State_ &= CONSTANT(!PedalDown)

{
This object serves as a controller for an individual voice as requested by the main synth object, and using that object to
accomplish what it does.
}
