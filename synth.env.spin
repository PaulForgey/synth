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

VAR
    LONG    LevelScale_         ' level scale for this iteration (0 <= n <= $400, $400 means full, <0 means pitch)
    WORD    LevelPtr_           ' long pointer to level in EG being managed
    WORD    GoalPtr_            ' long pointer to goal in EG being managed
    WORD    RatePtr_            ' long pointer to rate in EG being managed
    WORD    EnvPtr_             ' pointer to Envelope array (8 longs)
    WORD    RateScale_          ' rate scale for this iteration
    BYTE    State_              ' current state (0-3)

PUB Init(EgPtr, EnvPtr)
{{
EgPtr       : pointer to EG being controlled (6 longs)
EnvPtr      : pointer to envelope sequence of 8 longs (L1/R1..L4/R4)
}}
    LevelPtr_ := @LONG[EgPtr][0]
    GoalPtr_ := @LONG[EgPtr][1]
    RatePtr_ := @LONG[EgPtr][2]
    EnvPtr_ := EnvPtr
    State_ := 3

PUB Trigger(LevelScale, Reset, RateScale)
{{
LevelScale      : level scaling value 1-$400 if key down, 0 if key up
Reset           : reset EG back to 0 (or mid point for pitch)
RateScale       : rate scaling value 0-$1000
}}
    if LevelScale
        RateScale_ := $1000 - RateScale
        LevelScale_ := LevelScale
        if Reset
            SetEgRate($3fff_ffff)
            SetEgGoal(EnvLevel(3))
        SetState(0)
    else
        SetState(3)

PUB Panic
{{
Return to idle state with level at 0
}}
    LevelScale_ := 0
    RateScale_ := 0
    State_ := 3
    SetEgRate(0)
    SetEgGoal(0)
    SetEgLevel(0)

PUB Run
{{
Poll EG to possibly advance sequence and reprogram EG for next phase
}}
    ' state 2 requires a key up to get out of
    if State_ < 2 and EgLevel == EgGoal
        SetState(State_ + 1)

PRI SetState(s)
{{
Transition to new state
s       : state (0-3)
}}
    State_ := s
    SetEgRate(EnvRate(s))
    SetEgGoal(EnvLevel(s))

PRI EgLevel
{{
Return current level
}}
    return LONG[LevelPtr_]

PRI SetEgLevel(l)
{{
Set current level
l       : 0-$3fff_ffff
}}
    LONG[LevelPtr_] := l

PRI EgGoal
{{
Return EG goal
}}
    return LONG[GoalPtr_]

PRI SetEgGoal(g)
{{
Set EG goal
g       : 0-$3fff_ffff
}}
    LONG[GoalPtr_] := g

PRI SetEgRate(r)
{{
Set EG rate
r       : 0-$3fff_ffff
}}
    LONG[RatePtr_] := r

PRI EnvLevel(s)
{{
Return programmed EG level value for state, scaled according to Trigger
}}
    result := LONG[EnvPtr_][s << 1]

    if LevelScale_ < 0
        result := (result + LevelScale_)
    else
        result := (result >> 10) * LevelScale_

PRI EnvRate(s) | e
{{
Return programmed EG rate for state, scaled according to Trigger
}}
    e := $f000 - LONG[EnvPtr_][(s << 1) + 1]
    e := (e * RateScale_) >> 12
    e := $f000 - e

    result := WORD[$d000][e & $7ff] | $1_0000
    e >>= 11
    if e > 16
        result <<= (e - 16)
    else
        result >>= (16 - e)
    result <#= $3fff_ffff

