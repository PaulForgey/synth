HEXFILES=$(wildcard *.txt)

all: $(addsuffix .bin, $(basename $(HEXFILES)))

%.bin : %.txt
	xxd -r -p $< $@
