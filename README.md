Digital Synth for the Propeller
===============================

Cheap, simple but also useful

* 6 operators
* 4 LFOs
    * Sine
    * Triangle
    * Saw up
    * Saw down
    * Square
    * Noise
* 4 stage envelope
* Pitch envelope
* 8 voice polyphonic
* 20 bit sample depth of output (each oscillator is 17 bit)
* 44.1K sample rate
* each operator may use either sine or triangle waves as modulator or carrier

In some ways, the operation is similar to that of a DX7. In fact, most DX7 patches could be approximately transcribed. There are
a few major differences and limitations from a DX7:

* The LFOs are single tap, so they cannot resync per voice
* The oscillators do not resync
* Voices do not have an LFO delay
* Envelopes are linear, so they lack some of the subtlely the DX7's EG curve had

On the upside, there are 4 LFOs and the operators may use triangle waves. Like the DX-7, the oscillators have 4096 samples per
period from a 1024 sample lookup table, contributing to a familiar FM sound. Rate scaling is supported, but it needs work.

Circuit Design
==============

* Cirrus Logic WM8731 DAC
* SSD1305 OLED controller
* Winbond W32Q32FV flash
* 132x64 OLED display
* 3x 2 bit rotary encoding knob with buttons and RGB LED

There is nothing unusual in how the Propeller itself is wired into the circuit. The typical implementation in the Parallax
data sheet is used, including the 32K EEPROM. A Prop Plug is used for programming, wired into `RES`, `P31` and `P30` in the
usual way. As this is an audio circuit, use bypass caps on all ICs as near to them as possible.

This particular circuit is using a 10MHz crystal for the Propeller. A more standard 5MHz crystal may certainly be used, but be
sure to adjust `_clkmode` and `_xinfreq` if so.

The rotational encoders with pushbuttons all use diodes and pulldown resisters on their output, as each of the three controls
are polled by driving one of the three output pins high. The two outputs of the rotation plus the button provide 3 inputs.
This is in the very typical style of a keyboard matrix, in this case, 3x3. Three more pins are used to select which of three
cathods of the red, green or blue LEDs are active within the knobs. The knobs are white when not editing parameters specific
to any operator or LFO, and individually colored for the LFO or operator being edited otherwise.

The flash, OLED controller and DAC are all configured to use SPI. The flash memory stays in SPI (single) mode.
The DACs master clock is driven by one of the Propeller's PLL outputs. For I2S style communication for the DAC audio, the
Propeller uses a video shift register with two output pins made available. One for `DACLRC` and the other for `DACDAT`.

The `BCLK` comes from the PLL output being used to drive the video. This is actually undocumented Propeller behavior. The
"video mode" setting of the PLL exists to not waste a pin for it. Data is shifted out as the clock output goes down, thus
allowing the DAC to latch the data going up. Only data for the left channel is shifted out. The DAC will see all 0s for the
right channel.

The 32Mb/4MB flash size is probably overkill and any reasonable flash size addressable within a 24 bit address space may be used.
Any device used must be capable of erasing a 4KB sector.

To avoid another external component, the flash SPI pins are hooked up to a separate set of Propeller pins. To get the spare pins
back, use a buffer like a '244 to supply all devices' `DIN`, `CLK`, and `RESET` inputs.

Line level output from the DAC comes from only the left output, and requires an external amplifier to drive. The built-in
headphone amplifier is not used as driving both ears from a single output would overload the chip with 16 ohm headphones.

The output of the DAC was suprisingly quiet and stable on the breadboard. If the `DACDAT` related lines are left floating, it
seems rather sensitive to shifting in random noise. For power down, programming or if the Propeller crashes, I recommend 100K
pull-down resisters on these lines.

Programming Hints
=================

Feedback is a simple shift setting, so many of the lower settings may not have any audible effect, and the maximum setting is
pure noise with a very uneven spectrum. Setting `10` (out of a possible `1F`) is about equivilent to a more familiar maximum
effect.

The ability to use triangle waves is a little gimmicky, but very handy for recreating retro style sounds. As there is no low
pass filter found in waveshaping engines, using a triangle as a single carrier goes into full chip-tune sound.

A frequency is actually multiplied by adding pitch units. While this makes a setting like 3x awkward, it does allow for easily
setting multipliers at musical intervals. As with the DX7, (de)tuning is in pitch units of 1024 per octave. The minimal
granularity for frequency selection, relative or fixed, is within a pitch unit.

Be patient. Programming FM synths is a bit of a pain to do. My goal was to try to suck less than the Yamaha DX series in this
regard. I'm not sure if I succeeded or not. Supporting the MIDI data entry message would be quite helpful.

If modulator's transition across an envelope stage sounds horrible, try reducing its output. Between the ability to overmodulate
and the linearity of the EG curve, subtlety works better.

If someone actually builds this thing, uses it, and comes up with some patches that sound nice, I'd love to capture user
submissions in this repository.

Storing and Retrieving Patch Data
=================================

Selecting `DMP` in either the Load or Save menus will cause the patch data to be dumped as a hex formatted MIDI message out its
debug serial port (p30) at 31250-8-1-N (standard Propeller IDE settings). In raw binary form, this is a complete MIDI SysEx
message. In the Load menu, `DMP` will first load the patch. In the Save menu, the current patch in its current form will be
dumped with no flash interation. If the SysEx message is received, it will replace the working patch data but not save it to
flash.

The 3 ID bytes of the SysEx message is presumptuously $70 $7f $7f.
