# The 14 islands of Cyclone — master table at `$F230`

Cyclone's entire world is 14 fixed locations on a single 256×256 archipelago.
Missions / levels don't change the geography — only the objectives change.

The master table lives at `$F230` in the post-load snapshot. Each record is
20 bytes (`$14`); there are 14 records followed by an `$FF` end-marker at
`$F348`. The name of each record is looked up in the compressed stream at
`$6A50` (see `cyclone.ctl` for the decoder).

## Record layout

| Offset | Meaning |
| ------:| ------- |
| `+$00` | Object type byte (`$00` / `$01` / `$02`) |
| `+$01` | Sub-type (`$00` / `$01` / `$02`) |
| `+$02` | `x_min` — world X lower bound |
| `+$03` | `x_max` — world X upper bound |
| `+$04` | `y_min` — world Y lower bound |
| `+$05` | `y_max` — world Y upper bound |
| `+$06` | `z_min` — altitude lower bound |
| `+$07` | `z_max` — altitude upper bound |
| `+$08..+$09` | Secondary bounds |
| `+$0A..+$0B` | Runtime shape-work-buffer pointer (zero in a pre-init snapshot) |
| `+$0C..+$0D` | Display-file address for the projected shape |
| `+$0E..+$0F` | Extra work field |
| `+$10..+$11` | Unused by the name walker |
| `+$12` | Attribute-file high byte |
| `+$13` | `$00` — record terminator |

## The 14 islands

|  # | Address | Name              |   x range |   y range |   z range |
|---:|:--------|:------------------|----------:|----------:|----------:|
|  0 | `$F230` | BANANA ISLAND     |  92 – 168 | 128 – 184 | 114 – 146 |
|  1 | `$F244` | FORTE ROCKS       | 136 – 211 |   0 –  57 | 158 – 189 |
|  2 | `$F258` | KOKOLA ISLAND     |  87 – 161 | 148 – 204 | 109 – 139 |
|  3 | `$F26C` | LAGOON ISLAND     | 116 – 203 | 184 – 240 | 138 – 181 |
|  4 | `$F280` | PEAK ISLAND       |  40 – 101 |  88 – 144 |  62 –  79 |
|  5 | `$F294` | BASE ISLAND       |  28 – 130 |  80 – 136 |  50 – 108 |
|  6 | `$F2A8` | GILLIGANS ISLAND  |  28 –  94 |  88 – 145 |  50 –  72 |
|  7 | `$F2BC` | RED ISLAND        | 120 – 182 |  64 – 120 | 142 – 160 |
|  8 | `$F2D0` | SKEG ISLAND       | 112 – 173 |   0 –  56 | 134 – 151 |
|  9 | `$F2E4` | BONE ISLAND       | 172 – 255 | 124 – 180 | 194 – 233 |
| 10 | `$F2F8` | GIANTS GATEWAY    | 152 – 203 |  12 –  80 | 174 – 181 |
| 11 | `$F30C` | CLAW ISLAND       | 196 – 253 | 192 – 254 | 218 – 231 |
| 12 | `$F320` | LUKELAND ISLES    |  48 – 109 |  48 – 108 |  70 –  87 |
| 13 | `$F334` | ENTERPRISE ISLAND |  68 – 139 | 176 – 251 |  90 – 117 |

## ASCII archipelago (X: 0-255, Y: 0-255, top-down)

```
+----------------------------------------------------------------+
|                                                                |
|                                                                |
|                                   S       F                    |
|                                                                |
|                                            G                   |
|                                                                |
|                                                                |
|                   L                                            |
|                                     R                          |
|                                                                |
|               G P B                                            |
|                                                                |
|                                                                |
|                                                                |
|                                B                    B          |
|                                                                |
|                               K                                |
|                                                                |
|                                                                |
|                         E             L                        |
|                                                        C       |
|                                                                |
|                                                                |
|                                                                |
+----------------------------------------------------------------+
```

(Letters are each island's first letter. Where two islands share an initial,
the legend in `cyclone.ctl` disambiguates.)

## What's still unknown

The `+$0A/+$0B` shape-work-buffer pointers point into `$9300-$CFFF`, which
is entirely zero in the pre-init snapshot. That means the **island meshes
are computed at runtime by a 3D projector** — there's no static sprite per
island. The geometry source (either polygon coordinates, heightmap, or some
compact encoding) lives somewhere in the un-annotated data; finding it will
need tracing the code that populates `$9300+`.
