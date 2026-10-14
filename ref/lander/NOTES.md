# Lander (Archimedes) flight model and ship, reverse-engineered for a BBC port

Source: Mark Moxon's annotated reconstruction of David Braben's *Lander* (1987):
- site: https://lander.bbcelite.com/ (routine pages are under `https://lander.bbcelite.com/source/main/subroutine/<name>.html` and `.../variable/<name>.html`)
- repo: https://github.com/markmoxon/lander-source-code-acorn-archimedes, file `1-source-files/main-sources/Lander.arm`

Every number below was copied from `Lander.arm`. Anything I worked out myself rather than read off the source is marked **(inferred)**.

Files in this directory:

| file | what it is |
|---|---|
| `flight.py` | Integer reference model. `step(Ship, Inputs)` copies MoveAndDrawPlayer parts 1–3, LandOnLaunchpad, the crash test in DrawObject and the fuel burn, with Lander's 8-bit-operand multiply. It also has `step_lite()`, a 6502-friendly variant. Running it does a self-test, a 450-frame take-off, fly-around and landing, and a side-by-side run of the full and lite models. |
| `ship.py` | The `objectPlayer` blueprint, verbatim, plus Lander's shading rule and a PIL renderer. Running it writes `ship.json` and `ship.png`. |
| `ship.json` | Raw blueprint (hex and signed ints), values converted to tiles and unit normals, and the face list. |
| `ship.png` | Six perspective views with Lander's back-face test, blueprint-order fill and shading (hidden edges drawn dim), plus top and side orthographic wireframes. |

The earlier BBC attempt (github.com/ebenupton/virus) does **not** use Lander's ship or flight model. It has its own 6-vertex, 5-face (quad) ship and keyboard yaw/roll on Z/X/K/M. Thrust is 3×gravity (`GRAVITY_ACCEL=7`, `THRUST_ACCEL=21`, 16-bit velocities) with the same `v -= v>>6` drag. Its fixed-point layout and quarter-square multiplies are worth reusing, but the model below is the authentic one.

---

## 1. Coordinates and number formats

| quantity | format | source |
|---|---|---|
| position | signed 32-bit. **1 tile = `TILE_SIZE` = &01000000 (2^24)**, so the world wraps every 256 tiles in x and z. y covers only ±128 tiles. | config vars at top of Lander.arm |
| axes | x right, **y down** (smaller y = higher), z into the screen | GetLandscapeAltitude header |
| velocity | same units, per main-loop iteration ("frame") | MoveAndDrawPlayer pt 2 |
| angles | 32-bit, **full circle = 2^32**. The sine table is indexed by `angle >> 22` (1024 entries). | CalculateRotationMatrix, `sinTable` |
| unit vectors and matrix entries | **1.0 = 2^31** (`sinTable[n] = (2^31-1)·sin(2πn/1024)`) | `sinTable` |
| fuel | integer. Start 3413, refuel cap &1400 (5120). Bar length is `fuel>>4` pixels. | `initialFuelLevel`, LandOnLaunchpad, DrawFuelLevel |

Lander's multiplies (`CalculateRotationMatrix` rmat1–4, `GetDotProduct` dotp1–3) are shift-and-add over **only bits 30..23 of the first operand**. In practice every rotation-matrix product and every matrix×vector product is an **8-bit × 32-bit** multiply. `mul_lander()` in flight.py reproduces this exactly. For example, cos0·cos0 comes out as &7F7FFFFC, which is 255/256. So Lander already works at 8-bit angular precision, which is good news for a 6502.

## 2. Flight model, one main-loop iteration

Sources: MoveAndDrawPlayer parts 1–5 (`/source/main/subroutine/moveanddrawplayer_part_1_of_5.html` and so on), GetMouseInPolarCoordinates parts 1–2, CalculateRotationMatrix, LandOnLaunchpad, DrawObject part 2, DrawFuelLevel, StartNewGame, PlacePlayerOnLaunchpad, PrintCurrentScore. There is also the deep dive https://lander.bbcelite.com/deep_dives/flying_by_mouse.html.

### 2.1 Input → orientation (part 1, "flying by mouse")

1. `OS_Mouse` returns x, y and buttons `%lmr`. The button byte is stored directly as `fuelBurnRate`: left = 4 (full thrust), middle = 2 (hover), right = 1 (fire). If `fuelLevel == 0` then `fuelBurnRate = 0`.
2. `mx = min(x, 1023) - 512` (an unsigned cap, so it also catches negative values). `my = 512 - y`, so positive means the mouse was moved *down*, towards the player. y is not capped.
3. Both values are scaled `<< 22`, so 512 counts becomes 2^31.
4. **GetMouseInPolarCoordinates**:
   - The angle is `atan2(my, mx)`. It uses an 8-bit restoring divide of the smaller value by the larger, then a 128-entry `arctanTable` (`((2^31-1)/π)·atan(n/128)`), then octant folding in units of 2^29 (45°).
   - The distance is `sqrt(mx²+my²)/2`. The squares use the same 8-bit multiply (top byte only), and the square root comes from a 1024-entry `squareRootTable` (`(2^31-1)·sqrt(n/1024)`) indexed by `sum >> 22`.
5. The distance is capped below &40000000, then `<< 1`. The result is the **target pitch**: 1 mouse count gives 180/512 ≈ 0.35° of pitch, and 512 counts gives 180°. The angle is the **target direction**.
6. Damping and rate limit: `err = current − target`. For direction this is 32-bit wraparound, so it takes the shortest way round. `err` is clamped to ±&30000000 (67.5°; the negative clamp is −&30000001), then `current −= err >> 1`. So each frame the ship moves halfway to the mouse, by at most 33.75°.
7. `CalculateRotationMatrix(a = shipPitch, b = shipDirection)`:
   ```
   nose = ( cos a cos b,   sin a,  -cos a sin b)   model +x  (the gun fires along this)
   roof = (-sin a cos b,   cos a,   sin a sin b)   model +y  (points out of the floor = exhaust)
   side = ( sin b,         0,       cos b      )   model +z
   ```
   The matrix is stored row-wise (`xNose xRoof xSide / yNose … / zNose …`), so world = vx·nose + vy·roof + vz·side. A positive pitch tips the roof towards −x′, so thrust pushes the ship *towards* the mouse offset. Mouse right flies right (+x), mouse up flies into the screen (+z), and mouse back flies towards the viewer. Note that **ySide = 0**, so the y row is `(sin a, cos a, 0)`.

**Quirks (inferred from the code, and reproduced by flight.py):**
- **Pitch is quantised.** The square-root index is `(mx²+my²)/2^32 >> 22`, so the pitch target takes only the values 11.25°·√n. There is a **dead zone of about 32 mouse counts** where the pitch target is 0. The demo trajectory shows this: pitch settles at 15.9°, 19.5° or 22.5°, never at values in between.
- At the reset position (511, 511), `(mx, my) = (−1, +1)`, so the target direction is 135°. This has no visible effect because the pitch is about 0.
- The start values are `shipPitch = 1` and `shipDirection = 0` (PlacePlayerOnLaunchpad).

### 2.2 Thrust, drag, gravity, integration (part 2)

Order matters. For each axis:
```
if y < -HIGHEST_ALTITUDE:  fuelBurnRate &= ~%110        # engines cut above 52 tiles
v  = v - (v ASR 6)                                       # drag: 1/64 per frame
if burn & 4:  v -= roof ASR 11                           # FULL thrust ≈ 2^20 = 1/16 tile/f²
pos += v                                                 # integrate
if burn & 2:  v -= roof ASR 13                           # HOVER ≈ 2^18, applied AFTER the move
vy += gravity                                            # +&30000 (y is down)
```
The exhaust vector saved for particles is `roof`. Both thrust bits can be on together (left and middle buttons), giving 1.25× full thrust.

| constant | value | in tiles/frame or frame² | note |
|---|---|---|---|
| gravity, level 1 | **&30000** | 0.01172 | StartNewGame |
| gravity, score ≥ 1024 | **&50000** | 0.01953 | PrintCurrentScore |
| gravity, score ≥ 1488 | **&70000** | 0.02734 | PrintCurrentScore |
| full thrust | roof>>11, max ≈ **&FFFFF** | 0.0625 (5.33 g at level 1) | |
| hover | roof>>13, max ≈ **&3FFFF** | 0.0156 (1.33 g at level 1) | hover only *holds height* at level 1. At &50000 and &70000 it can't. **(inferred)** |
| drag | v ASR 6 | | terminal fall speed 64·g = 0.75 tiles/frame |
| HIGHEST_ALTITUDE | 52 tiles (y < −&34000000) | | thrust and hover are cut above this |

Fuel (DrawFuelLevel, called later in the same main-loop iteration): `fuel = max(0, fuel − fuelBurnRate)`. That burns 4 per frame on full thrust, 2 on hover, and 6 with both. Note that **the code subtracts the whole byte, so holding fire costs 1 per frame**. The commentary and the deep dive say bit 0 is ignored, but the instruction is `SUBS R1, R1, R2` on the unmasked `LDRB`. I've followed the code, but **this is uncertain**. The deep dive may describe intent, or something I haven't found may mask it. Also, when fuel = 0 the burn rate is forced to 0, so you can't fire either.

### 2.3 Ground, landing, crash (part 3, LandOnLaunchpad, DrawObject part 2)

```
safe_y = GetLandscapeAltitude(x, z) - UNDERCARRIAGE_Y                     # &640000 = 0.39 tiles
if 0 <= (safe_y - y) < SAFE_HEIGHT (1.5 tiles, unsigned compare):
    if objectMap[z>>24][x>>24] in 1..11:  crash                        # trees, buildings, rockets
if y > safe_y:                                                          # LandOnLaunchpad
    if x >= 8 tiles or z >= 8 tiles (unsigned):  crash                  # not over the pad
    if |vx|+|vy|+|vz| < LANDING_SPEED (&200000 = 1/8 tile/frame):
        y = LAUNCHPAD_Y (&3500000-&640000); v = 0
        if fuel+&20 < &1400: fuel += &20                                # refuel 32/frame
    # else: nothing happens yet ...
DrawObject: for each of the 9 ship vertices, project the vertex and the ground point below it.
    if screen_y(vertex) >= screen_y(shadow): crash                     # vertex at or under the ground
```
- The launchpad is `0 ≤ x, z < LAUNCHPAD_SIZE` (8 tiles) at `LAUNCHPAD_ALTITUDE` = &03500000. Sea level is &05500000. Ground is `LAND_MID_HEIGHT` (5 tiles) minus a 6-term sine sum/256 (GetLandscapeAltitude). It is implemented in flight.py.
- A landing that is too fast over the pad is *not* an immediate crash. The ship keeps sinking until a vertex reaches the pad, and then the vertex/shadow test kills it. That test works on **projected pixel rows**: `64 ± floor(256·y/z)` at the ship's depth of z = 15 tiles. So in effect it is "vertex within one pixel (~0.06 tile) of the ground", and it samples the ground under *each* vertex. A tilted ship can therefore clip a hillside with a wingtip.
- Sitting on the pad: gravity is added after the move, so the ship alternately sinks by one gravity step and gets snapped back. "landed" fires every other frame.
- Bullets (part 5): fire along nose/256 plus the ship velocity, and each one costs 1 point of score (`currentScore` starts at 500). These are out of scope here.

### 2.4 Frame rate

The main loop waits for vsync in SwitchScreenBank (`OS_Byte 19`), so all the per-frame constants are **per main-loop iteration at ≤50 Hz**. The source doesn't fix the actual frame rate on period hardware (my guess is 25–50 Hz, depending on scene complexity). Choose the BBC rate first, then rescale: if the BBC runs at half Lander's rate, double gravity and thrust (per frame²), use `v>>5` for drag, and double LANDING_SPEED.

## 3. Ship blueprint (`objectPlayer`)

Source: https://lander.bbcelite.com/source/main/variable/objectplayer.html and the deep dives `object_blueprints.html` and `drawing_3d_objects.html`. The header is `9, 9, offset, flags=%11` (rotates, has shadow).

**9 vertices, 9 triangular faces.** Coordinates are in tiles (raw ÷ 2^24, y down), and also given in **1/64 tile**, a suggested byte format for the BBC.

| v | x | y | z | ×64 |
|---|---|---|---|---|
| 0 | 1.0 | 0.3125 | 0.5 | 64, 20, 32 |
| 1 | 1.0 | 0.3125 | −0.5 | 64, 20, −32 |
| 2 | 0 | 0.0391 | −1.2 | 0, 2.5, −76.8 |
| 3 | −0.9 | 0.3125 | 0 | −57.6, 20, 0 |
| 4 | 0 | 0.0391 | 1.2 | 0, 2.5, 76.8 |
| 5 | −0.1 | −0.46875 | 0 | −6.4, −30, 0 (apex, top) |
| 6 | 0.3333 | 0.3125 | 0.25 | 21.3, 20, 16 |
| 7 | 0.3333 | 0.3125 | −0.25 | 21.3, 20, −16 |
| 8 | −0.2 | 0.3125 | 0 | −12.8, 20, 0 |

| face | verts | normal (÷2^31) | colour &rgb |
|---|---|---|---|
| 0 | 0 1 5 | 0.543, −0.764, 0 | &080 |
| 1 | 1 2 5 | 0.422, −0.783, −0.296 | &040 |
| 2 | 0 5 4 | 0.422, −0.783, 0.296 | &040 |
| 3 | 2 3 5 | −0.616, −0.631, −0.318 | &040 |
| 4 | 3 4 5 | −0.616, −0.631, 0.318 | &040 |
| 5 | 1 2 3 | −0.067, 0.900, −0.255 | &088 |
| 6 | 0 3 4 | −0.067, 0.900, 0.255 | &088 |
| 7 | 0 1 3 | 0, 0.9375, 0 | &044 (floor) |
| 8 | 6 7 8 | 0, 0.9375, 0 | &C80 (orange exhaust plate, coplanar with face 7 and drawn after it) |

Checks done by `ship.py`:
- Every normal has length exactly **0.9375** (15/16, i.e. &78000000).
- Every normal points outward from the centroid.
- Every normal is exactly parallel to its face's cross product. Winding is *not* consistent: faces 0–4 are wound one way and faces 5–8 the other. So Lander culls by the stored normals and never by winding. Use the normals.

Shape: the ship is a low five-sided pyramid. The wide edge v0–v1 is at +x, the point v3 is at −x, there are wingtips at z = ±1.2, the apex v5 is on top, and the floor is flat at y = +0.3125. The gun fires along +x (the nose vector). On the pad, the floor sits 0.078 tiles above the pad surface, because UNDERCARRIAGE_Y (0.39) is greater than the floor depth (0.3125).

### How Lander draws it (DrawObject parts 1–5)

1. **Transform.** Each vertex goes through MultiplyVectorByMatrix (9 dot products using the 8-bit multiply), then gets the object position added, then ProjectVertexOntoScreen (`x′ = 160 + 256·x/z`, `y′ = 64 + 256·y/z` on the 320×256 screen, worked out with normalising shifts and restoring division). The ship is always drawn at camera-relative `(0, max(yPlayer, 0), 15 tiles)`, so it stays in the centre of the screen and only drops when it is below y = 0. The camera follows `(x, min(y, 0), z + 5 tiles)`.
2. **Shadow points.** Every vertex is also projected at the ground altitude below it, and these points are used for the crash test.
3. **Back-face cull.** Rotate the face normal, then take `dot(object-centre vector, normal) < 0`. This uses the object *centre*, not the face, which is an approximation that suits small convex objects.
4. **Shadow.** If the rotated normal has y < 0 (it faces up), the face is drawn as a black triangle using the shadow points, one depth bucket further back.
5. **Shading.** `b = ((&80000000 − ny_rot) mod 2^32) >> 28`, plus 1 if `nx_rot < 0` (the light is above and slightly left), then `b = max(0, b − 5)`. Add b to each 4-bit channel of &rgb, clip at 15, and pack into a VIDC 256-colour byte. The source comment says "0 to 8" and "0..3", but by my arithmetic the range is 0..11 (up to 10 for these normals). **(inferred, and differs from the commentary.)**
6. **Depth sorting.** There is none inside an object. Visible faces are drawn in **blueprint order** (so face 8 lands on top of face 7). The whole object goes into one of the per-tile-row graphics buffers chosen by `zObject` (the "depth-sorting with the graphics buffers" deep dive), and the buffers are drawn back to front interleaved with the landscape rows.

## 4. Recommendations for the BBC port

**Model size.** 9 vertices, 9 faces. Usually 4–6 faces are visible. The underside (faces 5–8) shows whenever the ship tilts its floor towards the camera, i.e. when it thrusts into the screen. From the object-centre test, face 7 is visible when cos a·y_draw + 15·sin a·sin b < 0. **(inferred)**

**Suggested fixed point formats (all 6502-native):**
- Angles: bytes, 256 to the circle. Pitch 0..127 covers 0..180°.
- sin and cos: signed bytes ±127. This loses nothing, because Lander's own multiply keeps only 8 bits.
- Matrix: 8 signed bytes. ySide = 0, and yNose and yRoof are just sin and cos. Only the four cross terms need multiplies (quarter-square 8×8).
- Vertices: signed bytes at **1 tile = 64**. The largest value is ±77, so there is headroom. The 1/3- and 1/5-tile values round to 21 and 13.
- Normals: signed bytes. Lander's normals are exactly 120/128, so they fit a byte with room to spare.
- Position: 24-bit per axis at 2^15 per tile. Velocity: signed 16-bit at 2^−15 tile per frame (Lander >> 9). Then gravity is 384, full thrust is roof·16 (2032), hover is roof·4 (508), LANDING_SPEED is 4096, and drag is `v − (v>>6)`. `step_lite()` in flight.py implements exactly this. Over 160 frames it stays within about 1 tile of the full 32-bit model (see `compare_demo`).

**Input.** Keep Lander's feel with a **virtual mouse**. Keys nudge a signed-byte offset (sx, sy) and centre it on release (or not, to taste). Then:
- `target_dir = atan2(sy, sx)`: octant fold plus a 32-entry atan table.
- `target_pitch = |(sx, sy)|`: a 16×16 table or the `max + min/2` approximation.
- Apply the same "halve the error, cap at 48/256" damping.

Separate rotate and tilt keys would be simpler, but they lose Lander's characteristic control. Thrust, hover and fire map to three keys.

**Physics per frame.** Two 8×8 multiplies (sin a·cos b and sin a·sin b) give the roof vector. Three 16-bit drag subtractions, three thrust adds and three 24-bit position adds are fine. Allow about **0.6k cycles**.

**Crash test.**
- Replace the 9 per-vertex ground samples with one ground sample under the ship's centre (from bandfill's height field), plus a lowest-vertex test. The vertex height offset is `sin a·vx + cos a·vy`, two multiplies, for vertices 0, 1, 3 and 5 only.
- Landing: centre below `ground − undercarriage`, over the pad, and `|vx|+|vy|+|vz| < LANDING_SPEED`.

**Draw cost, rough estimate for a 2 MHz 6502** (the quarter-square 8×8 signed multiply is about 50 cycles):
- Matrix: 4 multiplies, about 0.3k cycles.
- Vertex rotation: 9 vertices × 8 multiplies, minus the zero terms, is about 60 multiplies plus 16-bit adds. About **4k cycles**.
- Projection: the ship's depth is fixed at about 15 tiles ± 1.2, so weak perspective (scale by 1/15, optionally with a `1 − rz/15` correction from a small table) costs about 9 × 2 multiplies. About 1k cycles. A true 1/z per vertex via a reciprocal table is about 1.5k.
- Back-face test: with the view vector (0, ≈0, 1), visibility is just the sign of the rotated normal's z, which is 3 multiplies per face. About 1.4k cycles. Shading needs the rotated normal's y as well (another 3 multiplies), about 1.4k cycles.
- Fill: the ship is roughly 30 × 15 MODE 1 pixels on bandfill's 256-wide screen (Lander's 256-pixel focal length at 15 tiles gives about 17 px per tile at 320 wide, so about 14 px per tile at 256 wide). With 4–6 small triangles, budget about **3–5k cycles** with a simple byte-span filler. Map the 0..11 brightness to bandfill's 2×2 CMY/black dithers.
- **Total: about 10–13k cycles per frame**, which is about 25–30% of a 50 Hz frame (40k cycles).
- Cheaper alternative: precompute the projected 9 vertices (2 bytes each) plus a visible-face mask and a shade per face for each of 32 directions × 16 pitches. That is 512 orientations × about 24 bytes, roughly **12 KB**, which fits the 32 KB sideways RAM budget. The transform then drops to almost nothing, and the per-frame ship cost becomes fill only (about 4–6k).
- A ground shadow can use the same projected points with y replaced by the single ground height under the ship. That is cheap, and it gives the important visual cue for altitude.

## 5. Uncertainties and things to check

- **Fuel cost of firing.** The code subtracts it (1 per frame); the commentary says it doesn't. See 2.2.
- **Brightness range.** I get 0..11 from the code; the commentary says 0..8 then 0..3. See the shading step in section 3.
- **Frame rate.** This is not knowable from the source. All constants are per main-loop iteration.
- **Lookup tables.** flight.py generates the tables from Moxon's formulas. They differ from the hard-coded EQUDs by ≤3 LSB in 2^31 (checked against the source), so they are not bit-exact.
- **Projection in the crash test.** `_project_y` models only the main branch of ProjectVertexOntoScreen (|y| ≤ z), which always applies at the ship's depth. Negative screen rows are not handled (they would be compared unsigned in the original).
- **Object map.** The object collision path is coded, but `object_at()` returns "no object". The landscape is implemented; objects are not.
- **Mouse units.** It's unclear whether OS_Mouse counts are per mickey or OS units in Lander's mode. The "32-count dead zone" is in whatever units OS_Mouse returns, centred on (511, 511).
