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

worldmap: images/cyclone-map.png images/cyclone-gameplay.png images/cyclone-full-map.png

# Capture two authentic in-game screenshots by replaying the RZX to specific
# frames and running sna2img.py on each resulting snapshot:
#   cyclone-map.png      — Cyclone's navigation map showing all 14 islands
#   cyclone-gameplay.png — isometric flight view with helicopter and terrain
images/cyclone-map.png: $(RZX) tools/render_map.py | $(BUILD)
	mkdir -p images
	rzxplay.py --no-screen --fps 0 --quiet --stop 20000 $(RZX) $(BUILD)/frame-map.z80
	sna2img.py -s 3 $(BUILD)/frame-map.z80 images/cyclone-map.png

images/cyclone-gameplay.png: $(RZX) | $(BUILD)
	mkdir -p images
	rzxplay.py --no-screen --fps 0 --quiet --stop 3000 $(RZX) $(BUILD)/frame-play.z80
	sna2img.py -s 3 $(BUILD)/frame-play.z80 images/cyclone-gameplay.png

# Reconstruct the full archipelago by scanning the RZX at 1500-frame
# intervals, picking the frame where the helicopter is best-centred over
# each of the 14 islands (using positions decoded from the master table at
# $F230), cropping the playfield, and compositing onto a 2048x2048 canvas.
SCAN_FRAMES := $(shell seq 100 1500 180000)
SCAN_DIR := $(BUILD)/scan

scan: $(SCAN_DIR)/.done

$(SCAN_DIR)/.done: $(RZX) | $(BUILD)
	@mkdir -p $(SCAN_DIR)
	@for f in $(SCAN_FRAMES); do \
	  test -s $(SCAN_DIR)/f$$f.z80 || \
	    rzxplay.py --no-screen --fps 0 --quiet --stop $$f $(RZX) $(SCAN_DIR)/f$$f.z80; \
	done
	@touch $(SCAN_DIR)/.done

images/cyclone-full-map.png: $(SCAN_DIR)/.done tools/build_full_map.py
	mkdir -p images
	python3 tools/build_full_map.py $(SCAN_DIR) images/cyclone-full-map.png

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
