# Lander reference

Reference material from *Lander* (David Braben, Acorn Archimedes, 1987), as
reconstructed and annotated by Mark Moxon:

- site: https://lander.bbcelite.com (routine pages at
  `/source/main/subroutine/<name>.html`, variables at `/source/main/variable/<name>.html`)
- source: https://github.com/markmoxon/lander-source-code-acorn-archimedes,
  `1-source-files/main-sources/Lander.arm`

Routine and constant names below are `Lander.arm`'s; every figure is from it.

| file | contents |
|---|---|
| `ship.py` | The `objectPlayer` blueprint (vertices, faces, normals, colours), Lander's rotation matrix, back-face test and shading rule, and a PIL render. `tools/shipgen.py` imports it. Run, it prints the blueprint checks and writes `ship.png`. |
| `flight.py` | The flight model transcribed: `step()` is one main-loop iteration of the player's ship, in Lander's 32-bit arithmetic with its truncated multiply and its tables. Nothing imports it; run, it self-tests. |
| `ship.png` | `ship.py`'s output: six perspective views as `DrawObject` would draw them, with the edges and vertex numbers over them, and top and side wireframes. |

## 1. Units

| quantity | format |
|---|---|
| position | signed 32-bit, `TILE_SIZE` = &01000000 (2^24) a tile, so x and z wrap at 256 tiles. x right, **y down** (altitude is −y), z into the screen. |
| velocity | the same, per main-loop iteration (a frame). |
| angle | 32-bit, 2^32 a circle (2^30 = 90°). `sinTable` has 1024 entries, indexed by `angle >> 22`. |
| unit vector | 2^31 = 1.0: `sinTable[n] = (2^31 − 1) sin(2πn/1024)`, `arctanTable[n] = ((2^31 − 1)/π) atan(n/128)` (128 entries), `squareRootTable[n] = (2^31 − 1) √(n/1024)` (1024 entries). |
| fuel | an integer; the bar is `fuel >> 4` pixels long on three rows (`DrawFuelLevel`). |

Multiplication (`CalculateRotationMatrix` rmat1–4, `GetDotProduct` dotp1–3) is
shift-and-add over bits 30..23 of one operand only, the other at full
precision: every rotation-matrix product and every matrix × vector product is
8 × 32 bits. cos 0 · cos 0 comes out as &7F7FFFFC. `flight.mul_lander` reproduces
it, with Lander's choice of truncated operand.

The main loop (`MainLoop`) runs `MoveAndDrawPlayer`, the particles, the objects,
the landscape, the score and fuel bar, then `SwitchScreenBank`, which waits for
vsync (OS_Byte 19). The constants are per iteration; the rate is whatever the
drawing allows, 50 Hz at most.

## 2. Camera and landscape

Constants (`Lander.arm`, configuration): `TILES_X` = 13 and `TILES_Z` = 11 tile
corners (12 × 10 tiles); `LANDSCAPE_X` = 5.5 tiles; `LANDSCAPE_Z` = 20 tiles;
`CAMERA_PLAYER_Z` = 5 tiles; `LANDSCAPE_Z_FRONT` = 10 tiles; `LANDSCAPE_Z_MID`
= 15 tiles; `LAND_MID_HEIGHT` = 5 tiles; `SEA_LEVEL` = &05500000 (5.3125 tiles);
`LAUNCHPAD_ALTITUDE` = &03500000 (3.3125 tiles); `LAUNCHPAD_SIZE` = 8 tiles.

**Camera** (`MoveAndDrawPlayer` part 3): `xCamera = xPlayer`,
`yCamera = min(yPlayer, 0)`, `zCamera = zPlayer + CAMERA_PLAYER_Z`. It looks
along +z, level. The camera follows the ship up but not down: below y = 0 the
ship drops down the screen instead.

**Landscape block** (`DrawLandscapeAndBuffers`): corner (i, j), i = 0..12
across and j = 0..10 from the back row, is projected at camera-relative
(i − 5.5 − fx, altitude − yCamera, 20 − j − fz) tiles, fx and fz the fractions
of `xCamera` and `zCamera` within their tiles; its world position is
(⌊xCamera⌋ − 5.5 + i, ⌊zCamera⌋ − j) tiles. The block therefore slides a whole
tile at a time, and the eye is 15 tiles behind the ship (`zPlayer − 15`), with
the block from 10 − fz to 20 − fz tiles in front of it and the ship in the
middle of it. The player's ship is drawn at camera-relative
(0, max(yPlayer, 0), `LANDSCAPE_Z_MID`) with the player's rotation matrix
(`MoveAndDrawPlayer` part 3).

**Projection** (`ProjectVertexOntoScreen`, MODE 13, 320 × 256):
x′ = 160 + 256 x/z, y′ = 64 + 256 y/z, the quotients truncated to whole pixels
and the signs applied; the vanishing point is row 64. A vertex with z negative
is not projected.

**Altitude** (`GetLandscapeAltitude`), the coordinates taken as angles (the
landscape repeats every 256 tiles):

```
y = LAND_MID_HEIGHT − [sin(x − 2z) + sin(4x + 3z) + sin(3z − 5x) + sin(7x + 5z)] / 128
                    − [sin(5x + 11z) + sin(10x + 7z)] / 256
```

with the sines at the 2^31 scale, so each of the first four spans ±1 tile and
the last two ±0.5: ±5 tiles about 5. Then y is clamped to `SEA_LEVEL` (ground
lower than the sea is raised to it), and over the pad, 0 ≤ x, z < 8 tiles
(unsigned), it is `LAUNCHPAD_ALTITUDE`.

**Tile colour** (`GetLandscapeTileColour`), from the corner's altitude word:
red 4 if bit 2 is set, else 0; green 4, plus 4 if bit 3 is set; blue 0. The pad
is grey (4, 4, 4); a tile whose corner and the corner before it are both at
`SEA_LEVEL` is blue (0, 0, 4). A brightness is added to all three channels and
each clipped at 15: the corner row (0 at the back, 10 nearest) plus
max(0, previous corner's altitude − this one's) >> 22, the previous corner being
the one before it in the row's left-to-right sweep (a tile of rise gives 4).

## 3. Flight model, one main-loop iteration

Transcribed in `flight.step`.

### 3.1 Mouse to attitude (`MoveAndDrawPlayer` part 1)

1. `OS_Mouse` returns x, y and the buttons %lmr, stored as `fuelBurnRate`: left
   = 4 (full thrust), middle = 2 (hover), right = 1 (fire). If `fuelLevel` is 0
   the burn rate is 0.
2. `mx = min(x, 1023) − 512` (an unsigned cap); `my = 512 − y`, positive when
   the mouse is pulled towards the player (RISC OS y increases up the screen).
   Both are scaled `<< 22`. `ResetMousePosition` puts the pointer at (511, 511),
   so at rest (mx, my) = (−1, 1).
3. `GetMouseInPolarCoordinates`: the angle is atan2(my, mx) (the smaller
   magnitude over the larger by an 8-bit restoring division, `arctanTable`, and
   the octant folded back in units of 2^29); the distance is
   `squareRootTable[(mx² + my²) / 2^54]`, about half the offset. With an
   offset of r counts the index is ⌊r²/1024⌋: the distance is 0 under 32 counts.
4. The distance, capped below &40000000 and doubled, is the **target pitch**:
   11.25° √⌊r²/1024⌋, so 11.25° at 32 counts, 22.5° at 64, 180° at 512. The
   angle is the **target direction**; at rest it is 135.2°.
5. Damping: err = current − target (the direction's wraps, so it takes the
   shorter way round). err > 0 is capped at &30000000 (67.5°); err <
   −&30000000 becomes −&30000001; then current −= err >> 1. Each angle moves
   halfway to its target, 33.75° a frame at most. For the pitch, err = 0 also
   takes the negative path (`BLE`, then `CMN`/`MVNLO` with no carry) and becomes
   −&30000001: a pitch that exactly reaches its target kicks up 33.75° for a
   frame and then settles from above. At rest the pitch is 1 and the target 0.
6. Start values (`PlacePlayerOnLaunchpad`): `shipPitch` = 1, `shipDirection`
   = 0, position (4 tiles, `LAUNCHPAD_Y`, 4 tiles), velocity 0.
7. `CalculateRotationMatrix(a = shipPitch, b = shipDirection)`:

   ```
   nose = ( cos a cos b,   sin a,  −cos a sin b)   model +x: the gun fires along it
   roof = (−sin a cos b,   cos a,   sin a sin b)   model +y: out through the floor; the thrust axis
   side = ( sin b,         0,       cos b      )   model +z
   ```

   stored row-wise (`xNoseV xRoofV xSideV / yNoseV … / zNoseV …`), so a model
   point rotates to vx·nose + vy·roof + vz·side. Thrust is along −roof: a
   positive pitch at b = 0 tips the roof towards −x, so thrust pushes the ship
   towards the mouse offset. Mouse right flies +x, mouse up (away from the
   player) flies +z into the screen, mouse down flies −z.

### 3.2 Motion (`MoveAndDrawPlayer` part 2)

In this order, each axis:

```
if y < −HIGHEST_ALTITUDE:  fuelBurnRate &= ~%110    # above 52 tiles the engines cut
v −= v ASR 6                                         # drag
if burn & 4:  v −= roof ASR 11                       # full thrust
pos += v
if burn & 2:  v −= roof ASR 13                       # hover, after the move
vy += gravity
```

The roof vector is kept as `xExhaust` for the exhaust particles. Both thrust
bits can be set at once.

| constant | value | tiles/frame or tiles/frame² |
|---|---|---|
| gravity (`StartNewGame`) | &30000 | 0.0117 |
| gravity from a score of 1024 (`PrintCurrentScore`) | &50000 | 0.0195 |
| gravity from a score of 1488 | &70000 | 0.0273 |
| full thrust | roof >> 11, up to 2^20 | 0.0625 (5.33 g at &30000) |
| hover | roof >> 13, up to 2^18 | 0.0156 (1.33 g at &30000) |
| drag | v >> 6 a frame | terminal fall 64 g: 0.75 tiles/frame at &30000 |
| `HIGHEST_ALTITUDE` | 52 tiles | |

The score starts at 500 (`initialScore`) and each bullet costs 1
(`MoveAndDrawPlayer` part 5).

### 3.3 Ground, landing, crash (`MoveAndDrawPlayer` part 3, `LandOnLaunchpad`, `DrawObject` part 2)

```
safe_y = GetLandscapeAltitude(x, z) − UNDERCARRIAGE_Y       # &640000 = 0.390625 tiles
if (safe_y − y) < SAFE_HEIGHT, unsigned:                     # within 1.5 tiles above it
    if objectMap[z >> 24][x >> 24] in 1..11:  crash
if y > safe_y:                                               # LandOnLaunchpad
    if x >= 8 tiles or z >= 8 tiles, unsigned:  crash        # off the pad
    if |vx| + |vy| + |vz| < LANDING_SPEED:                   # &200000 = 1/8 tile/frame
        y = LAUNCHPAD_Y; v = 0                               # &2EC0000 = 2.921875 tiles
        if fuel + &20 < &1400:  fuel += &20
    # else nothing: the ship sinks on until a vertex reaches the pad
DrawObject: for each of the 9 vertices, project it and the ground point below it;
    if the vertex's screen row >= its shadow's:  crash
```

- The vertex test works on pixel rows at the ship's depth of 15 tiles, so a
  vertex within about 0.06 tiles of the ground counts, and the ground is
  sampled under each vertex: a tilted ship can touch a slope with a wingtip.
- At rest on the pad gravity sinks the ship a step and `LandOnLaunchpad` puts
  it back, on alternate frames; so a parked ship refuels 32 every other frame,
  to a level below &1400 (5120).
- Fuel (`DrawFuelLevel`, later in the iteration): `fuel = max(0, fuel −
  fuelBurnRate)`, the whole byte, so 4 a frame on full thrust, 2 hovering, 6
  with both, and 1 for the fire button. The start level is 3413
  (`initialFuelLevel`).

## 4. Ship blueprint (`objectPlayer`)

Header: 9 vertices, 9 faces, flags %11 (bit 0: rotates, bit 1: casts a shadow,
as `MultiplyVectorByMatrix` and `DrawObject` read them). Coordinates in
tiles (raw / 2^24, y down); normals / 2^31; colours &rgb.

| v | x | y | z |
|---|---|---|---|
| 0 | 1.0 | 0.3125 | 0.5 |
| 1 | 1.0 | 0.3125 | −0.5 |
| 2 | 0 | 0.0391 | −1.2 |
| 3 | −0.9 | 0.3125 | 0 |
| 4 | 0 | 0.0391 | 1.2 |
| 5 | −0.1 | −0.46875 | 0 |
| 6 | 0.3333 | 0.3125 | 0.25 |
| 7 | 0.3333 | 0.3125 | −0.25 |
| 8 | −0.2 | 0.3125 | 0 |

| face | vertices | normal | colour |
|---|---|---|---|
| 0 | 0 1 5 | 0.543, −0.764, 0 | &080 |
| 1 | 1 2 5 | 0.422, −0.783, −0.296 | &040 |
| 2 | 0 5 4 | 0.422, −0.783, 0.296 | &040 |
| 3 | 2 3 5 | −0.616, −0.631, −0.318 | &040 |
| 4 | 3 4 5 | −0.616, −0.631, 0.318 | &040 |
| 5 | 1 2 3 | −0.067, 0.900, −0.255 | &088 |
| 6 | 0 3 4 | −0.067, 0.900, 0.255 | &088 |
| 7 | 0 1 3 | 0, 0.9375, 0 | &044 (the floor) |
| 8 | 6 7 8 | 0, 0.9375, 0 | &C80 (the exhaust plate, in the floor's plane, drawn after it) |

A low five-sided pyramid: the wide edge 0–1 at +x (the nose), the point 3 at
−x, wingtips 2 and 4 at z = ∓1.2, the apex 5 on top, the floor flat at
y = 0.3125. On the pad the floor is 0.078 tiles above the surface
(`UNDERCARRIAGE_Y` = 0.390625).

`ship.check_data` confirms: every normal has length 15/16 (0.9375) and points
outward; each is exactly parallel to its face's edge cross product, against
the winding for faces 0–4 and with it for 5–8, so Lander culls by the stored
normals, never the winding.

**Drawing** (`DrawObject`): each vertex is rotated (`MultiplyVectorByMatrix`,
the matrix entries the truncated operands), offset by the object's position and
projected; the ground point below it is projected too (`GetLandscapeBelowVertex`,
the shadow points, which also serve the crash test). Then for each face in
blueprint order: the normal is rotated; if its y < 0 (the face looks up) and the
flags' bit 1 is set, a black shadow triangle is drawn on the shadow points; the
face is culled if its rotated normal dotted with the object's position vector
is ≥ 0 (the object's centre, not the face's: an approximation that suits a small
convex object); otherwise shaded and filled. Nothing is sorted within an object;
the object as a whole goes into the graphics buffer for its depth.

**Shading**: brightness = ((&80000000 − ny) mod 2^32) >> 28, +1 if nx < 0,
−5, floored at 0, from the rotated normal (nx, ny): 0..11, brightest facing up
and a step brighter facing left. It is added to each 4-bit channel of &rgb,
clipped at 15, and packed into a VIDC 256-colour byte.

## 5. What this game takes

- `tools/shipgen.py` imports `ship.py`'s `VERTICES`, `FACES`, `TILE`, `ONE`,
  `rotation_matrix`, `mat_vec` and `lander_brightness`: the ship is rotated by
  Lander's matrix for every (pitch, direction) the BBC draws, culled by its
  normals against the fixed view vector, shaded by Lander's rule, and projected
  in parallel at 14 pixels a tile (its header).
- `src/game.s` follows section 3 with one step a frame at 10 frames a second,
  each step taken as 1.25 of Lander's (its header): gravity, full thrust along
  the roof vector, the 1/64 drag, the fuel burn and the refuel rate are 1.25
  times Lander's per step with the velocities kept in Lander's units, so
  `LANDING_SPEED` is unchanged; the refuel limit &1400 (5120) is the tank's
  size and the ship starts full (`initialFuelLevel` is not used); there is no
  hover: SPACE and SHIFT both give full thrust; the undercarriage is
  a quarter tile (`UNDER`, Lander's 0.39 scaled to the drawn ship); the engines
  cut once the land has left the screen (`HIGHEST_ALTITUDE` in effect). Its
  pad is 6 tiles (`PADN`) for Lander's 8, the ship 13 tiles from the camera
  (`ZSHIP`) for Lander's 15, the camera a fixed height above the ground under
  the ship, raised with the ship (`CAME`) rather than following `min(y, 0)`,
  and the attitude comes from keys in fixed steps (32 directions, 13 pitches
  10° apart) rather than the mouse.
- `proto/land.py` and `src/land.s` take section 2's block: 13 × 11 corners with
  the back row at 20 − fz and corners at i − 5.5 − fx, projected with Lander's
  256-pixel focal length onto a 256-pixel-wide screen (a narrower view, the line
  of sight at x = 128, the horizon above the screen), and the six-sine altitude
  formula, rescaled to 16 height units a tile over a 64-tile wrapping map with
  its own sea level. The tile colours are the game's own (`land.colour`), not
  Lander's rule.
