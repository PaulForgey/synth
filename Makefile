
# the specific device depends on individual Prop Plugs, change it to reflect yours
DEVICE=cu.usbserial-A903VR78
SPIN=/usr/local/bin/openspin
PROPMAN=/usr/local/bin/propman
PYTHON=/usr/bin/python
TARGET=synth

# copy string.integer.spin from the Propeller library or add an -I option to include it from where it is
DEPS=\
	synth.alg.table.spin \
	synth.eg.spin \
	synth.env.spin \
	synth.io.spin \
	synth.oled.spin \
	synth.osc.spin \
	synth.patch.data.spin \
	synth.patch.data.store.spin \
	synth.patch.spin \
	synth.spin \
	synth.tables.spin \
	synth.voice.spin \

all: $(TARGET).binary

install:: $(TARGET).binary
	$(PROPMAN) --device $(DEVICE) $<

burn:: $(TARGET).binary
	$(PROPMAN) --device $(DEVICE) -w $<

$(TARGET).binary:: $(DEPS)
	$(SPIN) $(TARGET).spin

clean:
	rm -f $(TARGET).binary
	rm -f synth.tables.spin

synth.tables.spin:: tables.py
	$(PYTHON) tables.py > $@


