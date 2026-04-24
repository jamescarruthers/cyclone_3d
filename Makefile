# SkoolKit disassembly pipeline for Cyclone (Vortex Software, 1985).
#
# Requires SkoolKit (https://github.com/skoolkid/skoolkit) on PATH.
# Install with: pip install skoolkit
#
# Targets:
#   make tape      # unzip the TZX tape files
#   make snapshot  # tap2sna.py -> build/cyclone.z80
#   make ctl-auto  # sna2ctl.py  -> build/cyclone.auto.ctl (machine-generated)
#   make skool     # sna2skool.py using the hand-curated cyclone.ctl
#   make html      # skool2html.py HTML disassembly under build/html
#   make clean

ZIP      := Cyclone.tzx.zip
TAPE_DIR := tzx
TAPE     := $(TAPE_DIR)/Cyclone - Side 1.tzx
BUILD    := build
SNAP     := $(BUILD)/cyclone.z80
AUTO_CTL := $(BUILD)/cyclone.auto.ctl
CTL      := cyclone.ctl
SKOOL    := $(BUILD)/cyclone.skool
HTML_DIR := $(BUILD)/html

.PHONY: all tape snapshot ctl-auto skool html clean

all: skool

$(BUILD):
	mkdir -p $(BUILD)

tape: $(TAPE)

$(TAPE): $(ZIP)
	unzip -o $(ZIP) -d $(TAPE_DIR)
	touch "$(TAPE)"

snapshot: $(SNAP)

$(SNAP): $(TAPE) | $(BUILD)
	tap2sna.py "$(TAPE)" $(SNAP)

ctl-auto: $(AUTO_CTL)

$(AUTO_CTL): $(SNAP) | $(BUILD)
	sna2ctl.py --hex $(SNAP) > $(AUTO_CTL)

skool: $(SKOOL)

$(SKOOL): $(SNAP) $(CTL) | $(BUILD)
	sna2skool.py --hex -c $(CTL) $(SNAP) > $(SKOOL)

html: $(SKOOL)
	skool2html.py -d $(HTML_DIR) $(SKOOL)

clean:
	rm -rf $(BUILD) $(TAPE_DIR)
