# SkoolKit disassembly pipeline for Cyclone (Vortex Software, 1985).
#
# Requires SkoolKit (https://github.com/skoolkid/skoolkit) on PATH.
# Install with: pip install skoolkit
#
# Targets:
#   make tape      # unzip the TZX tape files
#   make snapshot  # tap2sna.py -> build/cyclone.z80
#   make ctl-auto  # sna2ctl.py  -> build/cyclone.auto.ctl (machine-generated)
#   make map       # rzxplay.py  -> build/cyclone.map (execution trace from cyclone.rzx)
#   make ctl-rzx   # sna2ctl.py with -m map -> build/cyclone.auto-rzx.ctl
#   make skool     # sna2skool.py using the hand-curated cyclone.ctl
#   make verify    # reassemble and compare against the original snapshot
#   make html      # skool2html.py HTML disassembly under build/html
#   make clean

ZIP        := Cyclone.tzx.zip
TAPE_DIR   := tzx
TAPE       := $(TAPE_DIR)/Cyclone - Side 1.tzx
RZX        := cyclone.rzx
BUILD      := build
SNAP       := $(BUILD)/cyclone.z80
AUTO_CTL   := $(BUILD)/cyclone.auto.ctl
MAP        := $(BUILD)/cyclone.map
AUTO_RZX   := $(BUILD)/cyclone.auto-rzx.ctl
CTL        := cyclone.ctl
SKOOL      := $(BUILD)/cyclone.skool
REASM      := $(BUILD)/cyclone.reassembled.bin
HTML_DIR   := $(BUILD)/html

.PHONY: all tape snapshot ctl-auto map ctl-rzx skool verify html clean

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

map: $(MAP)

$(MAP): $(RZX) | $(BUILD)
	rzxplay.py --no-screen --fps 0 --quiet --map $(MAP) $(RZX)

midgame: $(BUILD)/cyclone-endgame.z80

$(BUILD)/cyclone-endgame.z80: $(RZX) | $(BUILD)
	rzxplay.py --no-screen --fps 0 --quiet $(RZX) $(BUILD)/cyclone-endgame.z80

worldmap: images/cyclone-world.png

images/cyclone-world.png: $(BUILD)/cyclone-endgame.z80 tools/render_map.py
	mkdir -p images
	python3 tools/render_map.py $(BUILD)/cyclone-endgame.z80 images/cyclone-world.png

ctl-rzx: $(AUTO_RZX)

$(AUTO_RZX): $(SNAP) $(MAP) | $(BUILD)
	sna2ctl.py --hex -m $(MAP) $(SNAP) > $(AUTO_RZX)

skool: $(SKOOL)

$(SKOOL): $(SNAP) $(CTL) | $(BUILD)
	sna2skool.py --hex -c $(CTL) $(SNAP) > $(SKOOL)

$(REASM): $(SKOOL)
	skool2bin.py $(SKOOL) $(REASM)

verify: $(REASM) $(SNAP)
	python3 tools/verify.py $(SNAP) $(REASM)

html: $(SKOOL)
	skool2html.py -d $(HTML_DIR) $(SKOOL)

clean:
	rm -rf $(BUILD) $(TAPE_DIR)
