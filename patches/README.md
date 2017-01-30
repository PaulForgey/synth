SysEx Message
=============

The highly presumptuous SysEx 3 byte ID sequence of `$70 $7f $7f` is used to receive patch data. This data is delicately
simplistic as it is a simple encoding scheme of the raw patch data with no version or key/value identifiers. To retrieve
the data from the device, capture the the serial output from pin 30 at 115200-8-1-N (standard setup for the Propeller IDE)
from the LOAD or SAVE menus. The 'DMP' button will, for Load, load the patch from flash and then dump it to the serial output.
For Save, the patch will be saved first to flash and then dumped.

In binary form which the `Makefile` will produce from `*.txt`, this is raw MIDI data which may be sent back to the device.
This replaces whatever patch data is running, so use this message carefully not to loose unflashed data.

[mido](https://github.com/olemb/mido) is one easy way to squirt MIDI data to any arbitrary output, for example:

```
import mido
output = mido.open_output(name='Your Output Device')
messages = mido.read_syx_file('violin.bin')
output.send(messages[0])
```

