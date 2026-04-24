# Cyclone (Vortex Software, 1985) — SkoolKit control file
#
# This file drives sna2skool.py. It was seeded by running
#   sna2ctl.py --hex build/cyclone.z80 > build/cyclone.auto.ctl
# which performs a static code/data analysis of the loaded snapshot, and was
# then hand-enriched with titles and block descriptions. Re-run `make ctl-auto`
# to refresh the seed whenever you want to compare against a fresh analysis.
#
# Control directives (column 1):
#   b = data block         t = text block          u = unused block
#   c = code block         w = word block          s = same-byte run
#   i = ignored            B/C/T/W/S = sub-block of another type
#   D = block description  N = (mid-)block comment
#   R = register value     E = block-end comment
#   M = multi-instruction comment
#   @ = ASM directive (@start, @org, @label=..., @equ=..., ...)
#
# Workflow for improving this file:
#   1. make skool                      # regenerate build/cyclone.skool
#   2. inspect build/cyclone.skool and spot mis-classified regions
#   3. adjust directives below (e.g. flip 'b' to 'c', split a block, add @label)
#   4. add titles / D / N annotations as routines become understood
#   5. goto 1
#
# Addresses are in hex ('$' prefix) because sna2ctl.py was invoked with --hex.
# -----------------------------------------------------------------------------

@ $4000 start
@ $4000 org
b $4000 Loading screen bitmap (display file)
D $4000 The 6144-byte Spectrum display file. Bytes are stored in the characteristic row-interleaved order: bit 7 = leftmost pixel, y coordinates are scrambled as (y2 y1 y0 y7 y6 y5 y4 y3).
D $4000 This area doubles as the first thing the tape loader paints onto the screen, and is reused by the game as the play area.
D $4888 These 18 bytes ($4888-$4899) form the tail of the graphics data block that starts well before and continues as $489A. The static analyser mis-identified them as a routine because CALL M,$FF0F (FC 0F FF) happens to be valid Z80 encoding — flipping to 'b' disassembles them as DEFB without changing any bytes.
b $5800 Loading screen attributes (attribute file)
D $5800 32 x 24 bytes of colour attributes (FLASH, BRIGHT, PAPER, INK). Written directly by the game to recolour the screen.
@ $5B00 label=MAIN_LOOP
c $5B00 Main game loop
D $5B00 Top-level per-frame routine entered after the SpeedLock loader finishes decryption. Calls #R$84D6 (clear screen), #R$8D0E (clear play area), #R$84F4 (reset play area tables) and #R$87BC to set up a fresh frame, then runs the per-frame pipeline: #R$76D2 input, #R$87F0/#R$91B4 object updates, #R$8B91 scroll, #R$8CA0 sprite tables, rendering, then #R$8B74 RNG tick, #R$85D4 end-of-frame housekeeping.
D $5B00 The two bytes at $5B5A-$5B5C sample ($7505), a game-mode flag: 01 means "in attract mode / demo" and jumps to #R$9246. Further branches check ($7526) joystick/input-method flags to decide which scanner to call (#R$762C vs #R$80AA).
D $5B00 Near the end, IN A,($FE) with A=$FD at $5BDD reads keyboard row A-G; if both A and G are held, the frame ends by jumping to the death/reset handler #R$E280.
N $5B71 Navigation-map redraw (one-shot, latched on bit 4 of ($7526)). When the player toggles the map view, the sequence at $5B73-$5B81 — RES 4 / LD ($7526) / CALL #R$8D0E (clear) / CALL #R$8D5D (paint islands + names) / CALL #R$8E5C (HUD) / CALL $8F6A (helicopter cursor) — repaints the nav-map screen seen in images/cyclone-map.png.
c $5B86 Frame dispatch (cursor/joystick variant)
D $5B86 Called from #R$5B00 when ($7526) bit 1 is clear (keyboard-only input).
c $5BEC Display "NO FUEL" message
D $5BEC Tail-call into #R$92D0 with HL pointing at the fixed message string at #R$5BF2. Triggered when the fuel counter reaches zero.
t $5BF2 " NO FUEL " message text
b $5BFB
b $5CB2 BASIC system-variables tail + a small helper fragment
D $5CB2 The bytes at $5CB2-$5CBA are end-of-BASIC-program markers (F0 FF FF FF 00 F0 01 21 F0) sitting inside the Spectrum's system-variables / BASIC VARS window. Marking them as 'c' as sna2ctl.py did produced the nonsense 'RET P / RST $38 / RST $38 / ...' sequence; flipping to 'b' renders them as DEFB without changing a byte.
D $5CB2 The ten bytes from $5CBB onwards (5F CD E8 19 22 BA 5C C9) encode 'LD E,A / CALL $19E8 / LD ($5CBA),HL / RET' — a short helper the BASIC loader used to call the ROM NEXT-LOOP routine at $19E8. It's preserved in the snapshot but unreachable from the loaded game, which is why keeping it as data is safe.
b $5CC3
t $5D08
b $5D0D
c $5D89 Explosion / noise sound effect (RNG-driven beeper)
D $5D89 Calls #R$8B74 to get a fresh random word, bails out via #R$842D if L is too low (under $46), then runs three rounds of a two-phase beeper wobble. Each round splits the random word into two 4-bit counters: one drives a high OUT ($FE),$10 pulse burst and the other a low OUT ($FE),$00 burst, producing the noisy "explosion" tones. Classic 48K Spectrum beeper with DJNZ timing.
s $5DBC
c $5DC5
b $5E0A
b $5E3E
b $5E59
b $5E94
b $5EA4
b $5EBF
b $5EC3
b $5EF6
b $5EFA
b $5F1A
b $5F20
b $5F24
b $5F26
b $5F28
b $5F2C
b $5F2E
b $5F4B
b $5F52
b $5F56
b $5F5B
b $5F60
b $5F62
s $5F64
b $5F66
b $5F92
c $5FDC Explosion sound effect (variant 2)
D $5FDC Identical structure to #R$5D89 — three-round RNG-driven beeper wobble via OUT ($FE). Only the exit label #R$842D is shared; the two routines are duplicated for different explosion types.
s $600F
c $6018
c $605D
@ $6072 label=RESET_OBJECTS
c $6072 Clear object table / reset sprite counter
c $6091
b $60AC
b $60E7
b $60F7
b $6112
b $6116
b $6149
b $614D
b $616D
b $6173
b $6177
b $6179
b $617B
b $617F
b $6181
b $619E
b $61A5
b $61A9
b $61AE
b $61B3
b $61B5
s $61B7
b $61B9
b $61E5
b $61E9
b $61EF
b $61F1
b $61F5
b $6211
b $6224
b $6231
b $6234
b $6249
b $624F
b $6264
b $6267
b $626C
b $626F
b $6271
b $6273
b $6275
b $6277
b $627C
b $627F
b $6281
b $6287
b $6291
b $6297
b $6299
b $629F
b $62A1
b $62A7
b $62B1
b $62B7
b $62BE
b $62CC
b $62CE
b $62D0
b $62D1
b $62D7
b $62D9
b $62DD
b $62E0
b $62E1
b $62E5
b $62ED
b $62F3
b $62F6
s $62F8
b $62F9
b $62FD
b $6314
b $631A
b $6334
b $633A
b $633F
b $6342
b $6346
b $635C
b $6362
b $6367
b $636A
b $636E
b $6372
b $6376
b $637F
b $6390
b $6396
b $639B
b $639E
b $63F6
b $63FF
b $6419
b $641D
b $642D
b $6430
b $6539
b $653D
b $6555
b $6558
b $6582
b $6586
b $65A6
b $65B2
c $6600 Scan table for terminator $2E
D $6600 Walks a 40-byte table at $6624 looking for the $2E ($.) marker and mutating it. Used to scroll or wipe the status line.
c $6616 Table-reset helper (used by $6600)
b $661C
b $661D
b $6625
b $6626
b $662E
b $6661
b $6665
b $6682
b $6686
b $6689
b $668C
b $669D
b $66A2
b $66A6
b $66B2
b $66C4
b $66D0
b $66F6
b $66FA
b $66FB
b $66FF
b $6709
b $670C
b $6795
b $6799
b $679D
b $67A2
b $67A5
b $67B2
b $67B3
b $67BA
b $67C4
b $67D0
b $67DA
b $67E5
b $6834
b $683E
t $6851
b $6888
b $68B4
b $68BA
b $68C4
b $68D0
b $68D1
b $68D6
b $68DA
b $68E5
b $69D2
b $69D6
b $69DA
b $69E8
t $6A50 Location name stream (shared world-map islands)
D $6A50 The 15 named *locations* on Cyclone's single shared archipelago map — NOT per-level maps. The same geography hosts every mission; only the objectives change between plays. Names: BANANA, FORTE ROCKS, KOKOLA, LAGOON PEAK, BASE, GILLIGANS, RED SKEG, BONE, GIANTS GATEWAY, CLAW, LUKELAND ISLES, ENTERPRISE, ISLAND.
D $6A50 Encoded as a control stream (see #R$8D5D): bytes $00-$FB index an 8-byte font at $6908; $FC terminates a char; $FD emits the shared '?ISLAND' suffix stored at #R$6AC2 (the '?' renders as a space in the font); $FE advances to the next object record; $FF ends the stream. Each location's bytes are pointed at by the IX+$10/$11 field in the 20-byte object records at $F230.
b $6A56
t $6A57
b $6A61
t $6A62
b $6A68
t $6A69
b $6A6F
t $6A70
b $6A74
t $6A75
b $6A79
t $6A7A
b $6A83
t $6A84
b $6A87
t $6A88
b $6A8C
t $6A8D
b $6A91
t $6A92
b $6AA0
t $6AA1
b $6AA5
t $6AA6
b $6AB4
t $6AB5
b $6ABF
t $6AC2
b $6AC9
b $6AE4
b $6AE8
b $6B11
b $6B16
b $6B2A
b $6B2D
b $6B49
b $6B4E
b $6B51
b $6B56
b $6B5B
b $6B5E
b $6B71
b $6B76
b $6B7A
b $6B7E
b $6B81
b $6B86
b $6B91
b $6B96
b $6BA9
b $6BAE
b $6BB1
b $6BB6
b $6BB9
b $6BBE
b $6BC1
b $6BC6
b $6BC9
b $6BCE
b $6BD1
b $6BD6
b $6C00
b $6C16
b $6C18
b $6C36
b $6C38
b $6C40
b $6C44
b $6C5E
b $6C60
b $6C68
b $6C6C
b $6C70
b $6C74
b $6C7F
b $6C92
b $6C94
b $6C9C
b $6CF6
b $6CFF
b $6D17
b $6D1D
b $6D2D
b $6D30
b $6E37
b $6E3E
b $6E55
b $6E58
b $6E82
b $6E86
b $6EA6
b $6EB2
c $6F00 Paint scoreboard text line
D $6F00 Copies a null($FF)-terminated string from $6624 onwards to the display-file address $507F (bottom of screen). Used to render score / status strings into the HUD.
b $6F24
b $6F5F
b $6F66
b $6F82
b $6F86
b $6F89
b $6F8C
b $6F9C
b $6FA2
b $6FA6
b $6FB2
b $6FC4
b $6FD0
b $6FF6
b $6FFA
b $6FFB
b $6FFF
b $7007
b $700B
b $7093
b $709A
b $709C
b $70A2
b $70A5
b $70B2
b $70B3
b $70BA
b $70C4
b $70D0
b $70DA
b $70E4
b $7162
b $7168
b $7178
b $7188
b $71B4
b $71BA
b $71C4
b $71D0
b $71D1
b $71D6
b $71DA
b $71E4
b $726B
b $7270
b $7273
b $7278
b $7280
b $7290
b $7298
b $72A8
b $72D2
b $72D6
b $72DA
b $72E8
b $7300
b $7304
c $7371
@ $7378 label=SOUND_TRIG
c $7378 Sound-trigger helper (conditional, from main loop)
c $7392
c $73A2
s $73B0
b $73B1
b $73B8
b $73E4
b $73E8
b $7422
b $7427
b $743A
b $743E
b $7442
b $7444
b $7447
b $747B
b $747E
b $7481
b $7486
b $7489
b $7491
b $74A9
b $74AC
b $74B9
b $74BC
b $74D1
b $74D4
b $74D6 Game state variables (starting bank)
D $74D6 Roughly 260 bytes of scalar game state plus two parallel 'save state' blocks. Addresses referenced by the code include: ($7500)/($7502) object X/Y, ($7504) control method (0=joystick,1=keys,3=cursor), ($7505) demo flag, ($7515)/($7516) level indices, ($7517) live level state, ($7522) packed input bits (from #R$7FD6), ($7526) menu/input-method bits, ($7527) difficulty, ($7528) pause flag, ($752D) dying flag, ($752E) mode switch, ($7537) three-frame counter (see #R$8B91), ($753B) active level, ($7555) explosion timer, ($7FD5) saved control method.
D $74D6 The blocks at $7560-$75A7 and $75C8-$75E7 look like two mirrored 72-byte save states (note $75C8 repeats the same $39 $01 $70 $01 header as $7560). Likely one is current, the other is the backed-up initial state used to restart the level.
b $754E
b $7550
c $762C Tile renderer — draw play area from object table
D $762C Called as the main frame renderer. Walks the object table at $F74E in 8 rows × 23 cols, for each entry reads a character index from $FE00+(IX), writes it to the attribute byte at $5800+offset, then copies 8 bytes of glyph bitmap from $FA00+(idx*8) to the display file. Classic Spectrum attribute-then-pixels character drawing.
s $76C9
c $76D2 Object-table init + visibility/bounds check
D $76D2 Clears the object tables at $F74E onwards, then scans incoming object position data in ($7500)-($7503), comparing against the bounds stored in a record pointed to by IX (fields at IX+0..IX+5: type, sub, x-min, x-max, y-min, y-max). Used to decide which enemies/fuel pods to render.
c $7717 Object-list advance (BC=$0014 per record)
D $7717 Called from #R$76D2 when an object fails the bounds check. Adds $0014 (20 bytes) to advance to the next object record.
c $7724
c $7737
c $774A
c $775E Object Y-extent check (variant)
D $775E Same shape as #R$7789 but reads IX+$08/$09 for the Y-extent, compares against ($7502).
c $7777 Object field read (IX+$0A/$0B as HL)
D $7777 Reads a 16-bit field from the object record at IX+$0A..IX+$0B into HL and combines it with the global ($7500) x-coordinate. Helper used by the collision/placement routines that follow.
c $7789 Object Y-bound check
D $7789 Reads IX+$0A..$0B into BC and IX+$08..$09 as the object's Y-range, compares against ($7502).
c $77AD Object-table iterator (helper)
c $77B7 Object-table iterator (helper 2)
c $77D2 Object-table iterator (helper 3)
c $77E8 Object bounds + X range check
D $77E8 Combines #R$7777 with a range compare against IX+$04 and the global ($7502).
c $7810 Object X-offset compute
D $7810 Computes (($7500) - IX+$02) + 1; used when mapping world coordinates to screen columns.
c $7854 Object render helper
c $787D Object render helper (variant)
c $788F Object render helper (variant 2)
c $78B1 Object render helper (variant 3)
c $78CF Jump table entry -> #R$77AD
D $78CF Start of a dispatch jump table whose entries are 3-byte JP instructions with variable padding. Likely indexed by an object-type register elsewhere.
s $78D2
c $78D3 Jump table entry -> #R$77B7
s $78D6
c $78D7 Jump table entry -> #R$77D2
s $78DA
c $78DF Jump table entry -> #R$77E8
s $78E2
c $78E3 Jump table entry -> #R$7810
s $78E6
c $78E7 Jump table entry -> #R$7854
s $78EA
c $78EF Jump table entry -> #R$787D
s $78F2
c $78F3 Jump table entry -> #R$788F
s $78F6
c $78F7 Jump table entry -> #R$78B1
s $78FA
c $7918 Indirect dispatch via $7A37 table
D $7918 Classic indexed JP: HL=$7A37, HL+=BC, then JP (HL) lands inside one of the 3-byte JP stubs at #R$7A37. BC is set by the caller to pick which object-class handler (#R$791D..#R$79FA) to invoke.
c $791D Object handler: bounds check + render 29-byte slab
D $791D Eight near-identical handlers follow ($791D, $7927, $793F, $7955, $797F, $79C2, $79E8, $79FA). Each reads ($7500)/($7502) against IX+$02..+$05 to translate world coords to screen offsets, then calls one of the blit primitives (#R$7777/#R$7789).
c $7927 Object handler variant 2
c $793F Object handler variant 3
c $7955 Object handler variant 4
c $797F Object handler variant 5
c $79C2 Object handler variant 6
c $79E8 Object handler variant 7
c $79FA Object handler variant 8
c $7A19 Object bounds prep (uses $79A6/$7789)
c $7A37 Second jump table -> #R$791D
D $7A37 Another dispatch table, parallel to the one at #R$78CF. Entries are 3-byte JP with variable padding.
s $7A3A
c $7A3B Jump table entry -> #R$7927
s $7A3E
c $7A3F Jump table entry -> #R$793F
s $7A42
c $7A47 Jump table entry -> #R$7955
s $7A4A
c $7A4B Jump table entry -> #R$797F
s $7A4E
c $7A4F Jump table entry -> #R$79C2
s $7A52
c $7A57 Jump table entry -> #R$79E8
s $7A5A
c $7A5B Jump table entry -> #R$79FA
s $7A5E
c $7A5F Jump table entry -> #R$7A19
b $7A62
b $7AC4
b $7AC8
c $7ADC Batch-update object state from work buffer
D $7ADC Copies 3x11 bytes (33 bytes) of object state from source pointer $F8B1 to destination $7A9F, advancing via POP DE/PUSH DE idiom in the inner loop.
s $7B9C
c $7BB8 Initialise work-buffer pointers (one-time)
D $7BB8 Sets the global pointers ($7510)=$7A9F (object scratch area), ($7509)=$FD48, ($750B)=$FE69. Called once from startup to wire the object-table pointers the rest of the engine dereferences.
c $7C3F
c $7C88
c $7C93
c $7CBC
c $7D20
c $7D4D
c $7DBF
s $7DE5
b $7DEE
b $7DF0
b $7DF4
b $7DF8
b $7DFB
b $7E01
b $7E04
c $7E0C
@ $7E10 label=UPDATE_HUD
c $7E10 Late-frame HUD / status update
c $7E77 Sprite blit loop (mode 1)
D $7E77 Reads bytes from DE, terminator $FE, stores to (HL) and advances HL with the Spectrum display-file stepping (INC D for intra-cell, ADD HL,BC for inter-cell). Five near-identical copies at $7E77, $7E9D, $7EC3, $7EE9, $7F0F handle different transfer modes (e.g. solid/masked/XOR).
c $7E9D Sprite blit loop (mode 2)
c $7EC3 Sprite blit loop (mode 3)
c $7EE9 Sprite blit loop (mode 4)
c $7F0F Sprite blit loop (mode 5)
c $7F21 Icon grid decrement + redraw
D $7F21 DEC C, saves registers, loads HL=$FCF8 (icon cache area), and continues the icon refresh loop for the scoreboard area.
b $7F98
b $7F9C
b $7FAC
@ $7FD6 label=READ_INPUT
c $7FD6 Keyboard / joystick input dispatcher
D $7FD6 Reads the control-method byte at ($7504): 00 = Sinclair-style joystick (falls through to #R$7FE8); 03 = cursor keys (jumps to #R$8079); anything else = custom keys (#R$8023). Each branch packs the movement/fire state into a single byte at ($7522) where bits 0-4 mean up/down/left/right/fire.
c $8023 Custom-keys input scanner
D $8023 Reads keyboard half-rows $EF (P-Y) and $F7 (1-5) and packs the resulting directions/fire flag into ($7522). Called from #R$7FD6 when the player has chosen a user-defined key layout.
c $8052
c $8079 Cursor-keys input scanner
D $8079 Reads half-rows $F7 (1-5) and $EF (P-Y) to pick up the Sinclair cursor keys (5=left, 6=down, 7=up, 8=right, 0=fire) and packs the resulting state in ($7522).
s $80A6
c $80AA Pause / attract-mode toggle (SPACE key)
D $80AA Polls half-row $7F (SPACE/B/N/M/SymShift) for SPACE, debounces it against a flag at ($7526) bit 0, and optionally beeps the ROM tone at $03B5 to acknowledge the keypress.
c $80D2
c $80D8
c $8104
c $8133
c $8152
c $81A6 Helicopter physics — self-modifying XY position update
D $81A6 The helicopter's world position is held in the 16-bit variables ($7500) and ($7502). Every frame this routine patches a single byte into each of two slots ($81EF and $81F6) and then runs through 'LD HL,(pos); <patched opcode>; LD (pos),HL' — the patched opcode is one of $00 (NOP, no move), $23 (INC HL, +1) or $2B (DEC HL, -1), selected from the delta table at #R$826F.
D $81A6 The index into #R$826F is derived from the current difficulty / skill dial at ($7527) and the menu state ($7516). $81B9-$81CE walks ($7527) in the range 0-7 depending on whether BIT 0 of C is set, and $81DC reads A=($7527) (or a copy in $753B) and uses it as the table offset. Each table entry is a pair (X-delta, Y-delta), so stepping by $0001 in the table advances both axes simultaneously.
D $81A6 The approach means the "engine" has zero inner-loop branching — the delta bytes are baked into the live instruction stream. Changing the helicopter's feel (faster / different trajectories) requires editing the table, not the code.
c $81CB Skill-dial increment (wraparound at 7)
D $81CB Increments ($7527), clamping at 7, then copies ($7506)->$753B and falls into #R$81A6 to apply the motion step. Called when BIT 0 of the joystick byte C fires (the "thrust" bit).
c $8214
c $8232
c $824C
c $8269
b $826F Helicopter motion delta table (opcode pairs)
D $826F 14 bytes = 7 pairs of (X-delta-opcode, Y-delta-opcode), each pair self-modified into #R$81A6 between the LD HL,(pos) and LD (pos),HL instructions. Decoded:
D $826F   0: ( $00 NOP , $2B DEC HL ) = move down
D $826F   1: ( $23 INC HL, $2B DEC HL ) = move right+down
D $826F   2: ( $23 INC HL, $00 NOP   ) = move right
D $826F   3: ( $23 INC HL, $23 INC HL) = move right+up
D $826F   4: ( $00 NOP , $23 INC HL ) = move up
D $826F   5: ( $2B DEC HL, $23 INC HL) = move left+up
D $826F   6: ( $2B DEC HL, $00 NOP   ) = move left
D $826F The missing 8th pair (left+down) may be encoded by the next 2 bytes at #R$827D ($2B $2B).
b $827D Likely tail of the motion table (left+down delta pair)
D $827D The first two bytes $2B $2B complete the 8-direction delta table started at #R$826F (left+down = DEC HL, DEC HL). The remaining four bytes $53 $4F $55 $54 spell 'SOUT' — probably the tail of a compass / heading string that lives nearby (not yet located).
c $8283
@ $8284 label=PRE_INPUT_TICK
c $8284 Pre-input tick (fuel/score decrement?)
c $82A7 Advance level timer, pop to title at $30
D $82A7 Increments ($7517); when it hits $30 branches to a level transition. Counts frames for the between-levels pause.
c $82C5
s $82D1
c $82D4 Scan buffer pointed to by ($751E)
D $82D4 Uses the 16-bit variable at $751E as a pointer, then walks through memory with DEC H to check bytes. Used by the cloud/parallax-layer handler.
c $82E7
c $82FB Zero a row via ($751E) pointer
D $82FB Writes $00 to whatever row ($751E) points at and advances H. Clears a scrolling strip.
c $830F
s $8320
c $8321 Clear scoreboard attribute column
D $8321 Zeros 10 bytes in the attribute area at $5AC0 stepping every $20 bytes — the left-hand scoreboard column. Used to wipe the fuel / score digits before redrawing.
c $8390
s $83BE
@ $83C2 label=ISR_BEEPER
c $83C0 Interrupt service routine (beeper tick) — real entry is $83C2
D $83C0 The RZX execution map proves that the actual entry point is #R$83C2, not $83C0. The game installs an IM 2 interrupt vector dynamically (see #R$FFDF notes): every 50Hz interrupt jumps to $FFF4, which the init code at $8C8C-$8C95 pokes full of 'JP $83C2'. The two bytes at $83C0-$83C1 ($44 $00, i.e. 'LD B,H; NOP') are padding.
D $83C0 The handler guards against re-entry via ($752D) and the demo-mode flag at ($7505). If the game is in normal play it reads a 4-bit sound mode from ($755D), sets up a pair of DJNZ delay counters (D and E), then loops 6-10 times driving OUT ($FE),$10 / OUT ($FE),$00 with the two delays — a standard 48K beeper square-wave generator. Exits via the common #R$842D tail which POPs all registers and EIs.
c $8404 Secondary entry to the beeper with different mode
s $8435
c $843A Pause-off + display-file scrub
D $843A Zeros the pause flag ($7528) then walks the display file from $47BE upwards doing byte-level clears. Cleanup before a new level.
c $844E Animate scoreboard byte-by-byte
D $844E Calls #R$6600 (scan) in a loop with decreasing delay counter ($00FF then step $0010). Used for the scoreboard wipe/reveal animation.
c $8470 Dispatch by ($752E) state
D $8470 Reads ($752E); if zero, jumps to #R$82A7; otherwise loads ($7517) and continues. State-machine switch for the current mode.
c $84AE Clear display column (from $4038)
D $84AE Walks the 24 rows of pixel column 8 in the display file, zeroing each byte. Uses the "INC H" stepping trick — one pixel row at a time.
@ $84D6 label=CLEAR_SCREEN
c $84D6 Clear screen (black paper, white ink)
D $84D6 Zero-fills the 6144-byte display file ($4000-$57FF), then paints $07 across the full 768-byte attribute file ($5800-$5AFF) giving white ink (bits 0-2) on black paper. Leaves HL at $5B00 on exit.
R $84D6 O:HL $5B00 (one past the attribute file)
s $84F2
c $84F4 Initialise attributes and icons around the play area
D $84F4 Copies 21 runs of 8 attribute bytes from the table at $7200 into alternating positions across attribute rows starting at $5818, then copies a 64-byte block from $7148 to $5AC0 (the last two attribute rows — the scoreboard). Finally iterates an icon/sprite-index table at $7300, unpacking up to 15 x 8 entries into character cells near $4018. Runs once per new level to paint the static HUD graphics.
b $85B9
b $85CB
b $85CC
c $85CF
@ $85D4 label=END_FRAME
c $85D4 End-of-frame housekeeping
c $864B
c $8681
s $86AC
c $86AF Object/frame counter update
D $86AF Zeros ($7512), increments ($750D), walks a pointer table at $FE66. Advances the per-frame counters used by #R$87F0.
c $8741
c $875A
c $8770
c $878D
c $87B9
@ $87BC label=FRAME_SETUP
c $87BC Pre-frame setup (reset rendering buffers)
c $87D2
c $87D8
s $87ED
b $87EF Single flag byte (loaded/stored by $89CE/$89DA/$8A1D/$8B36)
@ $87F0 label=UPDATE_OBJECTS
c $87F0 Object-update loop (physics + collisions)
c $883D
c $8844
c $88DD
c $88FF
c $891D
c $8929 ADD HL,DE * B (multiply helper)
D $8929 Classic Z80 multiplier: adds DE to HL in a tight DJNZ loop. Used by sprite code to advance rows by a variable step.
c $894C
c $8A49
b $8A69
b $8A6E
c $8A74
@ $8A7A label=FRAME_TIDY
c $8A7A Per-frame tidy (attribute refresh?)
c $8AC1
c $8B15 Wrapper: save BC, call #R$82D4
c $8B1D Input-value filter ($80, $86 → skip)
D $8B1D Dispatches on an input/control code: values $80 and $86 short-circuit via JR Z to $8B5D (probably "pause/menu" codes).
c $8B30 Range-check loop helper
c $8B49
c $8B4E
c $8B5D
b $8B63
@ $8B67 label=SET_IM1
c $8B67 Enable interrupt mode 1 (and EI)
D $8B67 Sets I to the value already in A then executes IM 1 / EI / RET. Used when the game needs the standard 48K ROM interrupt (e.g. while calling into the ROM BEEPER).
s $8B6D
@ $8B74 label=RANDOM
c $8B74 Pseudo-random number generator (system-variable seed)
D $8B74 Reads the 16-bit seed from Spectrum system variable SEED at ($5C76), mangles it with a sequence of SBC HL,DE / SBC A,$00 operations that implement a Lehmer-style multiply-and-modulo, then writes the new value back to ($5C76). Returns the new random word in HL.
D $8B74 Called from many places — the sound routine #R$5D89 uses it for noise pitch, object spawners use it for positions, etc.
R $8B74 O:HL new 16-bit random number
c $8B91 Frame counter (modulo 3)
D $8B91 Increments the byte at ($7537); when it wraps past 3, zeroes it and falls through to #R$8BA2. Drives one-in-three event timing.
c $8BA2 Three-frame tick handler
D $8BA2 Tail of the #R$8B91 counter: zeroes ($7537), calls #R$8B74 to advance the seed, sets D=1 as a reset flag for downstream calls.
c $8BC6 Select player-skill ladder
D $8BC6 Picks between two difficulty tables at $8C66 (keyboard) and $8C77 (joystick) based on ($7504), then indexes with ($7506). Feeds into #R$8BD5 / #R$8C19 which writes a self-modifying offset.
c $8BD2 Skill ladder (joystick path)
c $8C19 Self-modify skill constant (multiply-accumulate)
D $8C19 Multiplies HL by DJNZ count and pokes the result at $8C47 — classic self-modifying code to inline a constant into the speed/scroll loop.
c $8C35 Self-modify skill constant (cap at $07)
b $8C66
b $8C83
c $8CA0 Load sprite/character bank by index
D $8CA0 Reads indices from ($7504) and ($7507), walks a 72-byte-per-entry table starting at $E8E8 to find the selected bank, LDIRs the 72 bytes to $6950, then conditionally LDIRs further graphic strips to $7000 / $6700 based on ($7515)/($7516). Called once per level transition to swap in the correct ship / enemy frames.
c $8CEE
s $8D0A
@ $8D0E label=CLEAR_PLAY_AREA
c $8D0E Clear the play area (preserves scoreboard)
D $8D0E Writes $3F (FLASH|BRIGHT|white-on-white mask) across 22 rows of 23 columns of attributes from $5800 onwards — i.e. the left-hand 23x22 play area, leaving the rightmost 9 attribute columns alone for the HUD/scoreboard. Then walks the matching 23 pixel columns over 22 rows and zero-fills the bitmap using the classic 8x8 cell pattern (INC H 8 times, then INC HL and the RR H / RL H trick to advance one cell right). Called from #R$5B00 each frame.
@ $8D5D label=DRAW_NAVMAP
c $8D5D Render the navigation-map screen
D $8D5D Two-pass renderer for the in-game navigation map (see images/cyclone-map.png). Triggered from the main loop at $5B71-$5B81 when bit 4 of ($7526) is set: that path calls #R$8D0E (clear playfield to white-on-white), then #R$8D5D (this routine — draws icons + names), then #R$8E5C (HUD), then #R$8F6A (helicopter cursor).
D $8D5D Pass 1 ($8D5D-$8DDF): walks the 14-island master table at #R$F230 and decodes a small monochrome island-icon sprite for each, painting it at the screen position stored in the record. The sprite-decode loop at $8D7D-$8DA9 reads source bytes from `shape_base + $0102` (where shape_base = IX+$0A/$0B): for each output bit, it samples one source byte at stride 4 and sets the bit if the byte is >= $0F (so the source data is a 4-byte-per-pixel attribute-like stream that the renderer thresholds into a bitmap). IX+$0E gives the column count for the inner loop (sprite width in source samples), IX+$0F gives the row count for the outer loop (sprite height). Between rows the renderer adds $0200 to the source pointer (= 2 Spectrum scanlines) and advances the destination by one scanline. The destination starts at IX+$0C/$0D — a hand-laid display-file address that determines where on the nav-map screen this island's icon appears. (See `tools/extract_map.py:decode_navmap_sprite` for a Python reimplementation.)
D $8D5D Pass 2 ($8DE2 onwards): walks the same table again, this time following the pointer at IX+$10..$11 into the name stream at #R$6A4F and running the stream-walker at $8DEB:
D $8D5D   * character bytes $00-$FB are rendered via the 8-byte font at $6908 (see #R$8E15);
D $8D5D   * $FC bails on the current char;
D $8D5D   * $FD = emit the shared '?ISLAND' suffix (see #R$8E10);
D $8D5D   * $FE = advance to the next object record (IX += $14);
D $8D5D   * $FF = end of stream, RET.
D $8D5D The name data at $6A50 is therefore not 15 flat strings but a compact control stream shared across every named location the helicopter can fly to.
c $8D97 Shift-left multiplier (SLA C * B)
D $8D97 SLA C inside a DJNZ loop — i.e. C <<= B. Inline multiply-by-power-of-2. Used by #R$8D5D's sprite-decode pass to MSB-align the bit pattern when the inner loop exited early (E reached zero before all 8 inner iterations completed).
c $8E10 Emit '?ISLAND' suffix string from the name-stream
D $8E10 One of the control opcodes in the name-rendering stream ($FD) jumps here. Loads HL=$6AC2 which points at the "?ISLAND" string (and the "?" renders as a space), then falls into the character emitter at $8E15. Used to avoid repeating "ISLAND" in every level name in #R$6A50.
c $8E3D
s $8E53
c $8E5C Paint cockpit/HUD — fixed instrument panel
D $8E5C Draws the fixed cockpit graphics into the top-left corner of the display file. It walks ten small 8-byte sprite strips at $7438, $7440, $7448, $7460, $7470, $7480, $7488, $7490 (the radar frame, compass ring, altitude ticks, fuel-gauge outline, etc.) into fixed screen addresses ($4000, $4020, $4036, $50A0, ...). Then at $8EBC-onwards it calls #R$859A to stamp the single-character labels (digits, compass letters) from the inline strings at $8F0C+.
D $8E5C Called from the main init / screen-redraw sequence — not once per frame, since the HUD is static. The dynamic needles/markers are drawn on top by separate routines.
c $8EE8 Sprite blit inner loop (8 rows)
D $8EE8 Saves IX/DE, loops 8 times reading IX+$00..+$07 into the display file — the generic 1-cell-high, 8-pixel-tall blit kernel used by #R$8E5C and friends.
c $8F0C
@ $8F12 label=INPUT_ALT
c $8F12 Alternate input / joystick bit-1 handler
c $8F77 Multiply-by-B helper (ADD HL,DE loop)
c $8F95 Unmangle screen Y address (RR H x3)
D $8F95 Reverses the Spectrum display-file address scramble (y2 y1 y0 y7 y6 y5 y4 y3) by rotating H right 3 times then adding DE. Classic "convert pixel Y to character row" trick.
c $8FD0 Multiply-by-B helper (variant)
c $8FEE Unmangle screen Y address (variant)
b $901D
c $9034 Zero ($754D), load ($7500) shifted
D $9034 Initialises scoreboard helper: zeros the byte at $754D, then reads the object X coord and shifts H right by one (divides by 2) — probably mapping a world coordinate into a scoreboard icon column.
c $905B
c $9063
c $908E HUD/scoreboard refresh helper
c $9096 HUD/scoreboard refresh entry
c $90EA
c $9107
c $914F Frame-timing helper (pre-scoreboard)
c $9158 Frame-timing helper (post-scoreboard)
c $9169
b $9178
c $91B4 Clear attribute strip + draw status
D $91B4 Zeros 7 bytes in the attribute file starting at $591C (top-right of the scoreboard), then jumps into #R$91DA to repaint it.
c $91DA Scoreboard repaint (word-table indexed)
D $91DA Reads the level index from ($753B), uses it to index the word table at #R$9232, and writes the $47 attribute to the computed positions. Also paints a fixed strip starting at $58BA.
c $9201 Fill attribute column with $52
D $9201 Writes $52 (bright green ink on black paper) into every row of an attribute column — HL advances by DE ($0020 = one row) each iteration. Used when lighting up fuel / score indicators.
c $920A Fill attribute column with $7F
D $920A As #R$9201 but writes $7F (FLASH + bright + white-on-white). Used to draw the message-pending flash strip at $5A18.
c $921D
b $9232 Word table + game state variables (mis-classified as code)
D $9232 The 16 bytes at $9232-$9241 are used as a word table: #R$91DA indexes into it with BC and loads a 16-bit offset. The bytes from $9242 onwards are scalar game-state variables: ($9243) holds a 16-bit HL pointer (read by #R$92ED, updated by #R$928A etc.) and ($9245) holds a single-byte flag (toggled by $8394, $83B7, $928A, $929D, $92A1, $92CA).
@ $9246 label=ATTRACT_MODE
c $9246 Attract mode / demo handler
c $92C8 Display pop-up message (entry 1)
D $92C8 Sets the message-flash flag ($9245)=2 and HL=$8A6E, then falls into #R$92D0 which paints the 9-char line.
c $92ED XOR-blit sprite onto $6950 buffer
D $92ED XORs 72 bytes from the source pointer ($9243) into the buffer at $6950. Classic mask-less sprite blit into the off-screen character bank loaded by #R$8CA0.
b $9300
b $93C6
b $93CB
b $93E5
b $93E8
b $93F2
b $93F7
b $9443
b $944B
b $9471
b $947E
b $94A3
b $94A8
b $94C0
b $94C2
b $94CC
b $94E5
b $94E9
b $94F1
b $94FF
b $950C
b $9516
b $9523
b $952D
b $953F
b $9541
b $9542
b $954D
b $9561
b $9569
b $9571
b $957F
b $9589
b $9596
b $95A5
b $95AD
b $95C2
b $95CE
b $95E3
b $95E7
b $95F2
b $95FF
b $9609
b $9616
b $9623
b $9627
b $9628
b $9632
b $9647
b $964F
b $9663
b $9667
b $9672
b $967F
b $9689
b $968C
b $968D
b $9696
b $96A3
b $96B3
b $96C0
b $96C4
b $96C7
b $96D0
b $96E3
b $96E7
b $96F2
b $96F8
b $96F9
b $96FF
b $9709
b $9716
b $9723
b $9733
b $9741
b $9750
b $9763
b $9768
b $9772
b $977F
b $9784
b $9796
b $97A3
b $97AC
b $97AF
b $97B3
b $97BF
b $97D0
b $97E1
b $97EC
b $97F2
b $97FF
b $9803
b $9812
b $9823
b $982C
b $9830
b $9835
b $983F
b $9850
b $9861
b $986D
b $9872
b $987E
b $9882
b $988C
b $98AE
b $98B5
b $98BF
b $98C7
b $98CA
b $98D1
b $98E0
b $98F1
b $98F2
b $98FC
b $9905
b $9909
b $992D
b $9935
b $993F
b $9948
b $994B
b $9952
b $995F
b $9971
b $9972
b $997A
b $9982
b $9989
b $99AD
b $99B2
b $99BF
b $99C3
b $99CC
b $99D2
b $99DA
b $99E2
b $99EB
b $99F1
b $99F2
b $99FA
b $9A02
b $9A09
b $9A2A
b $9A32
b $9A3F
b $9A42
b $9A4B
b $9A4E
b $9A5A
b $9A62
b $9A6B
b $9A7A
b $9A82
b $9A88
b $9AAA
b $9AB2
b $9AC8
b $9ACC
b $9ADA
b $9ADD
b $9AE5
b $9AFA
b $9B2B
b $9B31
b $9B48
b $9B4C
b $9B4E
b $9B52
b $9B65
b $9B68
b $9B70
b $9B7A
b $9BB7
b $9BBC
b $9BC4
b $9BD2
b $9BE5
b $9BE8
b $9BF0
b $9BFA
b $9C44
b $9C52
b $9C65
b $9C68
b $9C70
b $9C7B
b $9CB7
b $9CBB
b $9CC3
b $9CD1
b $9CDA
b $9CDE
b $9CE3
b $9CE8
b $9CF0
b $9CFC
b $9D46
b $9D4F
b $9D5A
b $9D68
b $9D70
b $9D7F
b $9DC5
b $9DCE
b $9DDD
b $9DE5
b $9DF1
b $9DFF
b $9E47
b $9E4D
b $9E5D
b $9E64
b $9E79
b $9E7F
b $9F3F
b $9F45
b $9FB8
b $9FC2
b $9FC3
b $9FC6
b $A03B
b $A049
b $A0B8
b $A0C9
b $A138
b $A142
b $A143
b $A149
b $A1B8
b $A1C2
b $A1C6
b $A1C9
b $A206
b $A209
b $A246
b $A249
b $A286
b $A28A
b $A2A9
b $A2AD
b $A2C0
b $A2CB
b $A302
b $A30A
b $A329
b $A32D
b $A340
b $A34B
b $A385
b $A38A
b $A394
b $A396
b $A3C8
b $A3CB
b $A402
b $A40B
b $A413
b $A415
b $A429
b $A42C
b $A442
b $A445
b $A482
b $A488
b $A4C4
b $A4CA
b $A4DC
b $A4E7
b $A4EE
b $A4F9
b $A503
b $A508
b $A513
b $A517
b $A544
b $A54A
b $A55C
b $A567
b $A56E
b $A57A
b $A5C4
b $A5CA
b $A5DB
b $A5E7
b $A5EE
b $A5F7
b $A5F8
b $A5FC
b $A606
b $A60A
b $A65A
b $A667
b $A66E
b $A67C
b $A692
b $A69A
b $A6C6
b $A6C9
b $A6D9
b $A6F3
b $A6F6
b $A6FC
b $A713
b $A717
b $A759
b $A75E
b $A75F
b $A773
b $A776
b $A77C
b $A790
b $A799
b $A7C1
b $A7CB
b $A7DE
b $A7F9
b $A810
b $A819
b $A840
b $A84B
b $A85C
b $A87C
b $A890
b $A899
b $A8BC
b $A8C7
b $A8C8
b $A8CB
b $A8DC
b $A8FB
b $A939
b $A949
b $A95C
b $A962
b $A963
b $A97A
b $A9B8
b $A9C7
b $A9DC
b $A9EF
b $A9F4
b $A9FA
b $AA40
b $AA47
b $AA4A
b $AA57
b $AA5B
b $AA6F
b $AAC0
b $AAD8
b $AADB
b $AAE0
b $AAE9
b $AAF1
b $AB40
b $AB49
b $AB4A
b $AB58
b $AB6A
b $AB71
b $ABBD
b $ABD5
b $ABDB
b $ABE0
b $AC3F
b $AC58
b $AC5B
b $AC60
b $ACBE
b $ACC5
b $ACCD
b $ACD8
b $AD15
b $AD18
b $AD3E
b $AD45
b $AD4E
b $AD58
b $ADBE
b $ADC5
b $ADD2
b $ADD8
b $AE0C
b $AE18
b $AE38
b $AE3C
b $AE3E
b $AE44
b $AE4A
b $AE5D
b $AE5F
b $AE8B
b $AE95
b $AE96
b $AE9D
b $AEB9
b $AEBC
b $AEBE
b $AEC4
b $AEC9
b $AF05
b $AF07
b $AF0B
b $AF1E
b $AF39
b $AF45
b $AF84
b $AF86
b $AF8B
b $AF8E
b $AF8F
b $AFA0
b $AFB9
b $AFC4
b $B00D
b $B020
b $B039
b $B043
b $B068
b $B073
b $B08D
b $B093
b $B098
b $B0A3
b $B0B9
b $B0C2
b $B0E7
b $B0F4
b $B10C
b $B113
b $B118
b $B123
b $B13A
b $B142
b $B168
b $B17D
b $B18C
b $B193
b $B196
b $B1A3
b $B1BA
b $B1C2
b $B1E8
b $B1FD
b $B20E
b $B212
b $B216
b $B223
b $B23A
b $B241
b $B25D
b $B25F
b $B26A
b $B27D
b $B29A
b $B2A0
b $B2AA
b $B2AD
b $B2BA
b $B2C0
b $B2DC
b $B2DE
b $B2E4
b $B2E7
b $B2E8
b $B2F7
b $B2F8
b $B2FD
b $B31B
b $B320
b $B33A
b $B340
b $B34B
b $B351
b $B360
b $B36B
b $B371
b $B378
b $B39C
b $B3A0
b $B3A8
b $B3B2
b $B3BA
b $B3C0
b $B3CB
b $B3D5
b $B3DF
b $B3EB
b $B3F1
b $B3F6
b $B425
b $B433
b $B43A
b $B440
b $B44B
b $B457
b $B45F
b $B470
b $B471
b $B478
b $B4A5
b $B4B3
b $B4BA
b $B4D7
b $B4E7
b $B4F6
b $B529
b $B533
b $B53A
b $B544
b $B545
b $B54D
b $B54E
b $B557
b $B56A
b $B575
b $B5A9
b $B5B2
b $B5BA
b $B5C5
b $B5C6
b $B5CE
b $B5CF
b $B5D7
b $B5E7
b $B5EA
b $B5EB
b $B5F5
b $B642
b $B657
b $B668
b $B675
b $B6C2
b $B6D7
b $B6E9
b $B6EF
b $B746
b $B757
b $B769
b $B76F
b $B79F
b $B7AB
b $B7C7
b $B7D0
b $B81E
b $B822
b $B823
b $B82B
b $B89B
b $B8A2
b $B8A3
b $B8B2
b $B91B
b $B922
b $B923
b $B932
b $B99B
b $B9B7
b $BA1B
b $BA1E
b $BA1F
b $BA25
b $BA2A
b $BA37
b $BA9B
b $BA9E
b $BA9F
b $BAA5
b $BAAA
b $BAAD
b $BAAE
b $BABE
b $BB1B
b $BB1E
b $BB1F
b $BB25
b $BB2A
b $BB2D
b $BB2E
b $BB39
b $BB3C
b $BB3F
b $BB9A
b $BB9E
b $BB9F
b $BBB9
b $BBBC
b $BBC0
b $BC07
b $BC0D
b $BC19
b $BC27
b $BC28
b $BC3D
b $BC7B
b $BC7F
b $BC87
b $BC8D
b $BC98
b $BCA7
b $BCA8
b $BCAC
b $BCB7
b $BCC0
b $BCC6
b $BCCF
b $BCEF
b $BCF1
b $BCF5
b $BCFF
b $BD06
b $BD0D
b $BD18
b $BD21
b $BD22
b $BD2B
b $BD3B
b $BD40
b $BD46
b $BD50
b $BD76
b $BD7F
b $BD83
b $BD8D
b $BD98
b $BDA8
b $BDBD
b $BDC0
b $BDC6
b $BDD3
b $BDF2
b $BDFF
b $BE03
b $BE06
b $BE0B
b $BE0F
b $BE17
b $BE1C
b $BE24
b $BE28
b $BE39
b $BE40
b $BE49
b $BE53
b $BE71
b $BE7F
b $BE84
b $BE88
b $BE8B
b $BE93
b $BE97
b $BE9C
b $BEA5
b $BEA8
b $BEB6
b $BEBE
b $BEC6
b $BED4
b $BEF0
b $BEF4
b $BEFA
b $BEFF
b $BF05
b $BF13
b $BF15
b $BF1C
b $BF36
b $BF3E
b $BF45
b $BF55
b $BF7A
b $BF7F
b $BF95
b $BF99
b $BF9A
b $BF9D
b $BFCA
b $BFCE
b $BFD1
b $BFD6
b $BFEC
b $BFF3
b $BFFA
b $BFFE
b $C017
b $C01D
b $C04A
b $C04E
b $C051
b $C068
b $C06D
b $C072
b $C07A
b $C07E
b $C097
b $C09D
b $C0D2
b $C0DE
b $C0DF
b $C0F2
b $C0F9
b $C0FE
b $C124
b $C126
b $C134
b $C138
b $C152
b $C172
b $C176
b $C17F
b $C19B
b $C1A5
b $C1B4
b $C1B8
b $C1D2
b $C1F3
b $C1F6
b $C1FF
b $C21B
b $C21F
b $C251
b $C258
b $C259
b $C27F
b $C2D0
b $C2DA
b $C2F3
b $C2FC
b $C34F
b $C359
b $C374
b $C37F
b $C3CF
b $C3D5
b $C3F3
b $C3FB
b $C3FC
b $C3FF
b $C447
b $C454
b $C477
b $C47E
b $C4C7
b $C4D1
b $C4F4
b $C4FD
b $C548
b $C550
b $C578
b $C585
b $C5C9
b $C5CF
b $C60B
b $C60F
b $C68A
b $C68F
b $C69F
b $C6A2
b $C6DB
b $C6DF
b $C709
b $C70F
b $C71E
b $C723
b $C754
b $C75F
b $C788
b $C7A3
b $C7B0
b $C7B2
b $C7BE
b $C7C7
b $C7D4
b $C7DF
b $C807
b $C814
b $C819
b $C823
b $C82F
b $C831
b $C83D
b $C847
b $C854
b $C85C
b $C887
b $C88E
b $C899
b $C8A3
b $C8AE
b $C8B0
b $C8BD
b $C8C0
b $C8C1
b $C8C5
b $C8D4
b $C8E5
b $C907
b $C90A
b $C917
b $C923
b $C93D
b $C945
b $C951
b $C958
b $C95B
b $C966
b $C982
b $C984
b $C987
b $C98A
b $C992
b $C9A3
b $C9AE
b $C9B5
b $C9BD
b $C9C5
b $C9D0
b $C9D8
b $C9DB
b $C9E6
b $CA01
b $CA03
b $CA06
b $CA0D
b $CA0F
b $CA23
b $CA30
b $CA35
b $CA41
b $CA47
b $CA50
b $CA58
b $CA60
b $CA66
b $CA85
b $CAA3
b $CAA4
b $CAA8
b $CAAE
b $CAB5
b $CAC1
b $CAC7
b $CAD0
b $CAD3
b $CAE0
b $CAE6
b $CB05
b $CB08
b $CB09
b $CB1C
b $CB1D
b $CB20
b $CB24
b $CB28
b $CB50
b $CB53
b $CB5F
b $CB66
b $CB85
b $CB9F
b $CBA0
b $CBA3
b $CBA4
b $CBA8
b $CBD0
b $CBD3
b $CBDA
b $CBE6
b $CC05
b $CC13
b $CC1B
b $CC23
b $CC50
b $CC53
b $CC5C
b $CC66
b $CC85
b $CC92
b $CC99
b $CCA3
b $CCD0
b $CCD3
b $CCD4
b $CCDE
b $CCDF
b $CCE6
b $CD19
b $CD22
b $CD54
b $CD57
b $CD58
b $CD66
b $CD6B
b $CD6F
b $CDC8
b $CDCB
b $CDD4
b $CDE6
b $CDEB
b $CDEF
b $CE54
b $CE65
b $CE6B
b $CE6F
b $CED2
b $CEE4
b $CEEB
b $CEF6
b $CEFA
b $CEFF
b $CF52
b $CF5A
b $CF6B
b $CF70
b $CF73
b $CF7F
b $CFD2
b $CFDA
b $CFF3
b $CFFF
b $D03F
b $D044
b $D054
b $D058
b $D06E
b $D07F
b $D0A9
b $D0AC
b $D0C0
b $D0C4
b $D0D4
b $D0D8
b $D0EE
b $D0F8
b $D0F9
b $D0FF
b $D128
b $D12C
b $D13E
b $D142
b $D157
b $D15A
b $D176
b $D17F
b $D194
b $D197
b $D1A8
b $D1BC
b $D1F6
b $D1FE
b $D214
b $D218
b $D228
b $D23C
b $D23F
b $D242
b $D246
b $D24D
b $D276
b $D27B
b $D294
b $D29B
b $D2A9
b $D2B1
b $D2B4
b $D2BC
b $D2BF
b $D2C2
b $D2C6
b $D2CE
b $D2F6
b $D2FD
b $D314
b $D31C
b $D32A
b $D331
b $D334
b $D338
b $D33F
b $D342
b $D343
b $D34E
b $D356
b $D35C
b $D394
b $D39C
b $D3AC
b $D3B8
b $D3C2
b $D3C8
b $D3CB
b $D3CE
b $D40B
b $D41C
b $D42A
b $D42D
b $D44B
b $D44E
b $D46D
b $D46F
b $D488
b $D49C
b $D4AA
b $D4AD
b $D4C2
b $D4CD
b $D4EC
b $D4EE
b $D501
b $D506
b $D507
b $D517
b $D51B
b $D51F
b $D529
b $D52D
b $D542
b $D546
b $D56B
b $D56D
b $D581
b $D586
b $D587
b $D58B
b $D598
b $D59C
b $D59D
b $D5A0
b $D5E8
b $D5F0
b $D601
b $D606
b $D607
b $D60C
b $D615
b $D620
b $D667
b $D670
b $D681
b $D686
b $D687
b $D68F
b $D698
b $D69B
b $D69C
b $D6A0
b $D6C7
b $D6CE
b $D6E7
b $D6F6
b $D701
b $D706
b $D707
b $D70F
b $D743
b $D74F
b $D767
b $D777
b $D781
b $D78F
b $D791
b $D798
b $D79C
b $D7A0
b $D7A9
b $D7AB
b $D7C3
b $D7CF
b $D7E0
b $D7F7
b $D806
b $D80D
b $D81C
b $D820
b $D824
b $D82A
b $D83F
b $D847
b $D84C
b $D84F
b $D85F
b $D869
b $D86A
b $D877
b $D888
b $D88D
b $D89C
b $D8A3
b $D8A8
b $D8AC
b $D8BF
b $D8C7
b $D8CC
b $D8CF
b $D8DA
b $D8F7
b $D906
b $D90D
b $D91C
b $D923
b $D928
b $D92C
b $D93E
b $D941
b $D94C
b $D94F
b $D95A
b $D964
b $D965
b $D969
b $D974
b $D97A
b $D983
b $D98D
b $D99C
b $D9A3
b $D9A8
b $D9AD
b $D9B9
b $D9C1
b $D9CC
b $D9CF
b $D9DA
b $D9E4
b $D9F4
b $D9FA
b $DA01
b $DA06
b $DA09
b $DA0D
b $DA1C
b $DA23
b $DA28
b $DA2B
b $DA3E
b $DA41
b $DA4C
b $DA4F
b $DA65
b $DA68
b $DA75
b $DA7A
b $DA81
b $DA86
b $DA87
b $DA8D
b $DA9C
b $DAA2
b $DAA7
b $DABB
b $DAC0
b $DAC4
b $DACC
b $DACF
b $DAE2
b $DAE8
b $DAF5
b $DAFA
b $DB01
b $DB14
b $DB1C
b $DB22
b $DB29
b $DB39
b $DB3A
b $DB45
b $DB4C
b $DB4F
b $DB62
b $DB6E
b $DB81
b $DB8E
b $DB8F
b $DBA2
b $DBA7
b $DBCF
b $DBE2
b $DBEE
b $DBF5
b $DBFA
b $DC02
b $DC0B
b $DC0C
b $DC22
b $DC26
b $DC4E
b $DC65
b $DC6E
b $DC75
b $DC7A
b $DC83
b $DCA2
b $DCA7
b $DCB7
b $DCBE
b $DCCA
b $DCE8
b $DCF9
b $DD04
b $DD0C
b $DD19
b $DD21
b $DD28
b $DD2E
b $DD3E
b $DD4A
b $DD68
b $DD6B
b $DE1B
b $DE21
b $DF3E
b $DF41
b $DF46
b $DF4B
b $DF6C
b $DF72
b $E065
b $E06B
@ $E280 label=DEATH
c $E280 Death / game-over / reset sequence
D $E280 Entered when the player dies (low fuel with #R$5BEC, A+G key combo at $5BE9 in the main loop, or the IM2 handler at $8C9D). Sets the "dying" flag ($752D) to 1, plays a falling-tone beeper via ROM $03B5 (HL=$0666, DE=$0055), waits in a loop for #R$E3F8 to return NC, then calls #R$84D6 and #R$E2E8 to repaint. Finally reloads the saved control state from ($7FD5) and drops through to the menu at $E2BD.
c $E29E Title-screen key poll loop
D $E29E Polls the object-table scanner #R$FE92 and the keyboard wait #R$E3F8. Loops until a key in $30-$3F (digit 0-9) is pressed. Part of the "press key to start" logic on the menu.
c $E2E8 Paint HUD row from template at $E3A6
D $E2E8 Copies 13 bytes from $E3A6 into the attribute row at $58A9 (start of row 5). Used to repaint the status bar after a screen wipe.
b $E325
b $E327
b $E32C
b $E336
b $E337
b $E344
b $E345
b $E354
b $E355
b $E364
b $E366
b $E374
b $E376
b $E384
b $E385
b $E386
b $E394
b $E396
b $E3A4
b $E3A9
b $E3AC
b $E3B0
c $E3B3
c $E3F8 Read keyboard via ROM $028E / $031E
D $E3F8 Uses the Spectrum ROM's KEY_SCAN ($028E) and KEY_TEST ($031E) routines to return the next pressed key in A. NC on exit means a key was read.
c $E40C
c $E40F Walk a null($FF)-terminated list for A
D $E40F Reads bytes from HL until it hits $FF (return Z) or finds a match with the value in E. Small helper used to find a key in a lookup table.
b $E436
c $E473
b $E4E0
b $E504
b $E517
b $E51B
b $E51C
b $E521
b $E522
b $E527
b $E528
b $E52E
b $E52F
b $E537
b $E538
b $E544
b $E545
b $E558
b $E559
b $E56D
b $E56E
b $E57F
b $E580
b $E591
b $E592
b $E5A6
b $E5A7
b $E5BA
b $E5BB
b $E5D0
b $E5D1
b $E5DE
b $E5DF
b $E5EC
b $E5ED
b $E5F8
b $E5F9
b $E603
b $E604
b $E610
b $E611
b $E61B
b $E61C
b $E626
b $E627
b $E62F
b $E630
b $E638
b $E639
b $E63F
b $E640
b $E64E
b $E64F
b $E658
b $E659
b $E663
b $E664
b $E66C
b $E66D
b $E681
b $E682
b $E69A
b $E6B0
b $E6B7
b $E6C1
b $E6C9
b $E6CA
b $E6CD
b $E6DC
b $E6E1
b $E6E8
b $E6F0
b $E740
b $E744
b $E755
b $E758
b $E777
b $E77A
b $E77C
b $E780
b $E78B
b $E78F
b $E790
b $E794
b $E79F
b $E7A3
b $E7A5
b $E7A8
b $E7B3
b $E7B7
b $E7B8
b $E7BC
b $E7CC
b $E7D0
b $E7DC
b $E7DF
b $E7E0
b $E7E4
b $E808
b $E80C
b $E81C
b $E820
b $E830
b $E834
b $E844
b $E848
b $E858
b $E85C
b $EA17
b $EA1B
b $EA59
b $EA61
b $EA9C
b $EA9F
b $EB8F
b $EB92
b $EBD7
b $EBDA
b $EDD0
b $EDD4
b $EDDC
b $EDE0
b $EE1D
b $EE20
b $EE62
b $EE66
b $EF85
b $EF88
b $EFCB
b $EFCE
b $F009
b $F00D
b $F010
b $F014
b $F058
b $F05C
b $F0C5
b $F0C8
b $F217
b $F21A
b $F230 Island master table — 14 locations on the shared world map
D $F230 The 20-byte-per-record table that defines every named island in Cyclone. Decoded structure (offsets from the record start, matched to the reads in #R$76D2 / #R$7777 / #R$8D5D / #R$8DEB):
D $F230   +$00  type byte     (values $00/$01/$02 — graphic/category)
D $F230   +$01  sub-type      (values $00/$01/$02)
D $F230   +$02  x_min         world X lower bound
D $F230   +$03  x_max         world X upper bound
D $F230   +$04  y_min         world Y lower bound (compared with ($7502) at $770A)
D $F230   +$05  y_max         world Y upper bound
D $F230   +$06  z_min         altitude / Z lower bound
D $F230   +$07  z_max         altitude / Z upper bound
D $F230   +$08..+$09          secondary bounds (altitude mid / size?)
D $F230   +$0A..+$0B          runtime shape-work-buffer pointer (populated by the 3D projector, zero in this pre-init snapshot)
D $F230   +$0C..+$0D          navmap_screen_addr — display-file address where this island's icon is painted on the navigation-map screen (#R$8D5D pass 1)
D $F230   +$0E                navmap_sprite_width — column count for #R$8D5D's inner sprite-decode loop
D $F230   +$0F                navmap_sprite_height — row count for #R$8D5D's outer sprite-decode loop
D $F230   +$10..+$11          unused by the name walker (self-modified slot, see #R$8DEB)
D $F230   +$12                attribute-file HIGH byte for the paint target
D $F230   +$13                $00 — record terminator byte
D $F230 The 14 records map 1:1 to the 14 named locations in the name stream at #R$6A50 (BANANA ISLAND, FORTE ROCKS, KOKOLA ISLAND, LAGOON ISLAND, PEAK ISLAND, BASE ISLAND, GILLIGANS ISLAND, RED ISLAND, SKEG ISLAND, BONE ISLAND, GIANTS GATEWAY, CLAW ISLAND, LUKELAND ISLES, ENTERPRISE ISLAND). Each name is either $FD-terminated (renderer appends ' ISLAND') or $FE-terminated (rendered as-is).
D $F230 An $FF byte at $F348 marks the end of the table — #R$8D5D bails when IX+$00 = $FF.
D $F230 Decoded island world coordinates (centres/bounding boxes):
D $F230   $F230  BANANA ISLAND      x= 92-168  y=128-184  z=114-146
D $F230   $F244  FORTE ROCKS        x=136-211  y=  0- 57  z=158-189
D $F230   $F258  KOKOLA ISLAND      x= 87-161  y=148-204  z=109-139
D $F230   $F26C  LAGOON ISLAND      x=116-203  y=184-240  z=138-181
D $F230   $F280  PEAK ISLAND        x= 40-101  y= 88-144  z= 62- 79
D $F230   $F294  BASE ISLAND        x= 28-130  y= 80-136  z= 50-108
D $F230   $F2A8  GILLIGANS ISLAND   x= 28- 94  y= 88-145  z= 50- 72
D $F230   $F2BC  RED ISLAND         x=120-182  y= 64-120  z=142-160
D $F230   $F2D0  SKEG ISLAND        x=112-173  y=  0- 56  z=134-151
D $F230   $F2E4  BONE ISLAND        x=172-255  y=124-180  z=194-233
D $F230   $F2F8  GIANTS GATEWAY     x=152-203  y= 12- 80  z=174-181
D $F230   $F30C  CLAW ISLAND        x=196-253  y=192-254  z=218-231
D $F230   $F320  LUKELAND ISLES     x= 48-109  y= 48-108  z= 70- 87
D $F230   $F334  ENTERPRISE ISLAND  x= 68-139  y=176-251  z= 90-117
D $F230 IX+$0A/$0B is a base pointer into the island shape data at $9300-$CFFF. That region is empty in this pre-init snapshot but is populated once the SpeedLock loader has finished — see the mid-gameplay snapshot from `make midgame`. The base address is used by two distinct render paths:
D $F230   * Flight mode (#R$7777): each byte of the 256-byte block at `shape_base` is a tile-index into the 8x8 font at $FA00. The flight engine reads HL = base + (($7500) - IX+$06) and renders that character into the projected display-file slot. The non-zero tile indices map to per-tile OBJECTS (people, palm trees, fuel pods, etc.) that are placed across the island at flight scale — NOT a silhouette of the coastline.
D $F230   * Navigation-map mode (#R$8D5D): the renderer reads from `shape_base + $0102` instead, decoding it through a 4-byte-stride threshold-and-pack loop into a small monochrome island-shape icon. Each island has a unique sprite at this offset; e.g. BANANA's nav-map sprite source is at $9402, GILLIGANS at $9456, GIANTS at $9439.
D $F230 Multiple sparse islands share a 256-byte page (e.g. BANANA+GILLIGANS+GIANTS all live in $9300-$93FF at offsets 0, $54, $37). See ISLANDS.md for the flight-mode object layouts and `build/cyclone-map.json` for the decoded nav-map sprites.
@ $F34A label=FLASH_HUD
c $F34A Border/HUD flash (late-frame)
c $F35A
c $F37A
s $F38B
c $F39A Level-timer / explosion animation stepper
D $F39A Advances the animation counter at ($7555). If we're within the first 16 frames of an explosion, jumps to #R$F4AB; otherwise continues linearly.
c $F3D6
c $F3DC
c $F425
c $F42F
c $F4AB Cap animation delta against ($751B)
D $F4AB Clamps the remaining-frames value (A) against the max at ($751B); used inside the explosion stepper to avoid overshoot.
c $F4CC
b $F511
b $F517
b $F51D
b $F52D
b $F538
b $F548
b $F54A
b $F54E
b $F550
b $F56D
b $F571
b $F5B2
b $F5B7
b $F5FA
b $F5FD
b $F606
b $F609
b $F65D
b $F65F
b $F7F4
c $F80F
b $F889
b $F8AE
b $F8B6
b $F8C5
b $F8D7
b $F8EA
b $F90A
s $F921
b $F923
c $F926
s $F969
b $F96A
b $F9A5
b $FAE8
b $FAEB
b $FAF8
b $FAFB
b $FB00
b $FB04
b $FB80
b $FB89
b $FB8E
b $FB92
b $FB95
b $FC28
b $FC3D
b $FC41
b $FC45
b $FC49
b $FC4D
b $FC51
b $FC55
b $FC56
b $FC5A
b $FC5F
b $FC64
b $FC6B
b $FC6F
b $FC75
b $FC7D
b $FC87
b $FC8A
b $FC8F
b $FC94
b $FC9B
b $FCB9
b $FCC2
b $FCC8
b $FCD8
b $FCE7
b $FE00
b $FE0B
b $FE0F
b $FE16
b $FE17
b $FE1B
b $FE2D
b $FE31
b $FE33
b $FE4A
b $FE53
b $FE56
b $FE57
b $FE5B
b $FE80
b $FE83
b $FE84
b $FE8A
c $FE92 Scan 38-entry pointer table at $FF07
D $FE92 38 bytes ($26) starting at $FF07 get scanned; entries equal to $FF are skipped. Likely a table of active object slots.
c $FEB9 Copy-byte-via-saved-pointers helper
D $FEB9 Pops HL and DE from the stack, reads (DE)->(DE in original target). Used with the push/pop pattern in #R$FE92 to thread two pointers through a nested scan.
b $FEFF
b $FF13
b $FF2C
b $FF3F
b $FF63
s $FF70
b $FF71
s $FF73
b $FF74
b $FF78
b $FF8C
b $FF8F
b $FF94
b $FF97
b $FFA4
b $FFA7
b $FFA9
b $FFAF
b $FFB9
b $FFBF
b $FFC1
b $FFC7
b $FFC9
b $FFCF
b $FFD9
b $FFDF Graphics bytes + IM 2 interrupt vector trampoline (runtime-patched)
D $FFDF Most of this block is end-of-map graphics data. The three bytes at $FFF4-$FFF6 are special: in this pre-init snapshot they still contain uninitialised junk ($10 $10 $10), but the setup code at $8C8C-$8C95 POKEs them with $C3 $C2 $83 ('JP #R$83C2') just before executing 'LD A,$3A; LD I,A; IM 2'. The Spectrum's IM 2 interrupt vector ends up at I*256+$FF = $3AFF in the 48K ROM, whose ROM bytes happen to be $F4 $FF — so each interrupt jumps to $FFF4, which then JPs to the real handler. Classic Spectrum IM 2 trick.
b $FFF9
b $FFFF
