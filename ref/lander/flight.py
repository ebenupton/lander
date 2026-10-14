#!/usr/bin/env python3
"""
Lander (Archimedes, 1987) flight model -- integer reference implementation.

Faithful re-implementation of the player-ship physics from Mark Moxon's
reconstructed source (https://lander.bbcelite.com/, Lander.arm):

  MoveAndDrawPlayer parts 1-3  .../source/main/subroutine/moveanddrawplayer_part_1_of_5.html (..part_3_of_5)
  GetMouseInPolarCoordinates   .../source/main/subroutine/getmouseinpolarcoordinates_part_1_of_2.html
  CalculateRotationMatrix      .../source/main/subroutine/calculaterotationmatrix.html
  GetLandscapeAltitude         .../source/main/subroutine/getlandscapealtitude.html
  LandOnLaunchpad              .../source/main/subroutine/landonlaunchpad.html
  DrawObject part 2 (crash)    .../source/main/subroutine/drawobject_part_2_of_5.html
  DrawFuelLevel (fuel burn)    .../source/main/subroutine/drawfuellevel.html
  StartNewGame / PlacePlayerOnLaunchpad / PrintCurrentScore (initial values,
  gravity levels)

All quantities are 32-bit two's-complement as on the ARM:
  * position:   1 tile = 2^24.  x right, y DOWN (smaller y = higher), z into
                the screen.  The launchpad occupies 0 <= x,z < 8 tiles.
  * velocity:   same units, per main-loop iteration ("frame").
  * angles:     full circle = 2^32 (so 2^30 = 90 degrees).
  * unit vecs:  1.0 = 2^31 (sine table entries are (2^31-1)*sin).
The ARM multiplies used by Lander (shift-and-add) only use 8 bits of one
operand; mul_lander() reproduces that exactly.

step(state, inputs) advances one frame and returns a list of events.
"""
import math
from dataclasses import dataclass, field

# ---------------------------------------------------------------- constants
TILE_SIZE = 0x01000000
LAUNCHPAD_ALTITUDE = 0x03500000
SEA_LEVEL = 0x05500000
LANDING_SPEED = 0x00200000          # |vx|+|vy|+|vz| must be below this
UNDERCARRIAGE_Y = 0x00640000        # centre of ship -> bottom (0.39 tiles)
LAUNCHPAD_Y = LAUNCHPAD_ALTITUDE - UNDERCARRIAGE_Y
LAUNCHPAD_SIZE = TILE_SIZE * 8
HIGHEST_ALTITUDE = TILE_SIZE * 52   # engines cut when y < -this
SAFE_HEIGHT = TILE_SIZE * 3 // 2    # object-collision check band
LAND_MID_HEIGHT = TILE_SIZE * 5
TILES_Z = 11
CAMERA_PLAYER_Z = (TILES_Z - 6) * TILE_SIZE      # 5 tiles
LANDSCAPE_Z = TILE_SIZE * (TILES_Z - 1) + 10 * TILE_SIZE   # 20 tiles
LANDSCAPE_Z_MID = LANDSCAPE_Z - CAMERA_PLAYER_Z  # 15 tiles: ship depth

GRAVITY_LEVELS = (0x30000, 0x50000, 0x70000)  # score <1024, >=1024, >=1488
INITIAL_FUEL = 3413
FUEL_REFUEL_STEP = 0x20             # per frame while sat on the pad
FUEL_REFUEL_LIMIT = 0x1400          # store only if result < this
ANGLE_STEP_CAP = 0x30000000         # max |target - current| used per frame

BTN_FIRE, BTN_HOVER, BTN_THRUST = 1, 2, 4   # OS_Mouse %lmr: r=1 m=2 l=4

M32 = 0xFFFFFFFF


def s32(v):
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v


def asr(v, n):
    return s32(v) >> n          # Python >> on ints is arithmetic


# ------------------------------------------------------------------- tables
# Generated with the formulas documented in Lander.arm. These match the
# hard-coded EQUD tables to within 3 LSB (of 2^31) -- checked against source.
SIN = [int((2**31 - 1) * math.sin(2 * math.pi * i / 1024)) for i in range(1024)]
ATAN = [int((2**31 - 1) / math.pi * math.atan(i / 128)) for i in range(128)]
SQRT = [int((2**31 - 1) * math.sqrt(i / 1024)) for i in range(1024)]


def sin32(angle):
    """LDR Rx, [sinTable, angle LSR #20] with bits 20,21 cleared."""
    return SIN[(angle & M32) >> 22]


def cos32(angle):
    return sin32(angle + 0x40000000)


# --------------------------------------------------------- Lander multiply
def mul_lander(a, b):
    """Exact model of Lander's shift-and-add multiply (CalculateRotationMatrix
    rmat1..4, GetDotProduct dotp1..3): result ~= a*b / 2^31, but only bits
    30..23 of |a| are used (8-bit multiplier), |b| is full precision."""
    neg = (s32(a) < 0) != (s32(b) < 0)
    A = abs(s32(a)) & M32
    B = abs(s32(b)) & M32
    carry = (A >> 30) & 1                     # MOVS R2, R2, LSL #2
    r2 = ((A << 2) & M32) & 0xFE000000 | 0x01000000
    r3 = (B << 1) & M32
    acc = 0
    while True:
        r3 >>= 1
        if carry:
            acc = (acc + r3) & M32
        carry = r2 >> 31
        r2 = (r2 << 1) & M32
        if r2 == 0:
            break
    acc >>= 1
    return s32(-acc if neg else acc)


def _square_lander(x):
    """GetMouseInPolarCoordinates pole5/pole6: x*x / 2^32 using the top 8
    bits (31..24) of x as the multiplier."""
    carry = (x >> 31) & 1
    r3 = ((x << 1) & M32) & 0xFE000000 | 0x01000000
    r0, acc = x, 0
    while True:
        r0 >>= 1
        if carry:
            acc = (acc + r0) & M32
        carry = r3 >> 31
        r3 = (r3 << 1) & M32
        if r3 == 0:
            break
    return acc


def _div8(n, d):
    """8-bit restoring division n/d for n <= d: floor(256 n / d), max 255."""
    if d == 0:
        return 255
    return min(255, (n << 8) // d)


def mouse_polar(mx, my):
    """GetMouseInPolarCoordinates. mx,my = scaled mouse coords (<<22).
    Returns (distance, angle) with angle = atan2(my, mx) (2^32 = circle) and
    distance = r/2 (same scale as inputs)."""
    q = 0
    if s32(mx) < 0:
        q ^= 3
        mx = -s32(mx)
    if s32(my) < 0:
        q ^= 7
        my = -s32(my)
    ax, ay = mx & M32, my & M32
    if ax < ay:
        q ^= 1
        r = _div8(ax, ay)
    else:
        r = _div8(ay, ax)
    ang = ATAN[r >> 1]
    if q & 1 == 0:
        ang = (ang + (q << 29)) & M32
    else:
        ang = (((q + 1) << 29) - ang) & M32
    sumsq = (_square_lander(ax) + _square_lander(ay)) & M32
    dist = SQRT[(sumsq >> 22) & 1023]
    return dist, s32(ang)


def rotation_matrix(a, b):
    """CalculateRotationMatrix(a = shipPitch, b = shipDirection).
    Returns dict of the nine entries (1.0 = 2^31):
       nose = (cos a cos b,  sin a, -cos a sin b)
       roof = (-sin a cos b, cos a,  sin a sin b)   <- exhaust/thrust axis
       side = (sin b,        0,      cos b)"""
    sa, sb, ca, cb = sin32(a), sin32(b), cos32(a), cos32(b)
    return dict(
        xNose=mul_lander(ca, cb), yNose=sa, zNose=-mul_lander(ca, sb),
        xRoof=-mul_lander(sa, cb), yRoof=ca, zRoof=mul_lander(sa, sb),
        xSide=sb, ySide=0, zSide=cb)


def rotate(m, v):
    """MultiplyVectorByMatrix: matrix entries are the 8-bit-truncated operand."""
    x, y, z = v
    return (s32(mul_lander(m['xNose'], x) + mul_lander(m['xRoof'], y) + mul_lander(m['xSide'], z)),
            s32(mul_lander(m['yNose'], x) + mul_lander(m['yRoof'], y) + mul_lander(m['ySide'], z)),
            s32(mul_lander(m['zNose'], x) + mul_lander(m['zRoof'], y) + mul_lander(m['zSide'], z)))


# ---------------------------------------------------------------- landscape
def landscape_altitude(x, z):
    """GetLandscapeAltitude: y of the ground (bigger = lower), 32-bit coords."""
    x, z = s32(x), s32(z)
    r0 = asr(sin32(x - 2 * z), 7)
    r0 += asr(sin32(4 * x + 3 * z), 7)
    r0 += asr(sin32(3 * z - 5 * x), 7)
    r0 += asr(sin32(7 * x + 5 * z), 7)
    r0 += asr(sin32(5 * x + 11 * z), 8)
    r0 += asr(sin32(10 * x + 7 * z), 8)
    alt = s32(LAND_MID_HEIGHT - r0)
    if alt > SEA_LEVEL:
        alt = SEA_LEVEL
    if (x & M32) < LAUNCHPAD_SIZE and (z & M32) < LAUNCHPAD_SIZE:
        alt = LAUNCHPAD_ALTITUDE
    return alt


# ------------------------------------------------- crash test via shadows
def _project_y(y, z):
    """ProjectVertexOntoScreen main case (|y| <= z): 64 +/- floor(256|y|/z)."""
    q = ((abs(y) << 9) // z) >> 1
    return 64 + q if y >= 0 else 64 - q


def _ship_vertices():
    try:
        from ship import VERTICES          # same directory
        return VERTICES
    except ImportError:                     # fallback copy (tiles * 2^24)
        return [(0x01000000, 0x500000, 0x800000), (0x01000000, 0x500000, -0x800000),
                (0, 0xA0000, -0x1333333), (-0xE66666, 0x500000, 0),
                (0, 0xA0000, 0x1333333), (-0x199999, -0x780000, 0),
                (0x555555, 0x500000, 0x400000), (0x555555, 0x500000, -0x400000),
                (-0x333333, 0x500000, 0)]


SHIP_VERTICES = _ship_vertices()


def vertex_below_shadow(state, m):
    """DrawObject part 2: crashedFlag is set if any vertex projects on or
    below (screen y >=) its shadow, i.e. the vertex is at/under the ground
    to within one screen pixel at the ship's depth (~0.06 tile)."""
    y_cam = min(state.y, 0)                   # yCamera
    y_draw = max(state.y, 0)                  # y passed to DrawObject
    for v in SHIP_VERTICES:
        rx, ry, rz = rotate(m, v)
        zrel = LANDSCAPE_Z_MID + rz
        wx, wz = s32(state.x + rx), s32(state.z + rz)
        shadow = landscape_altitude(wx, wz) - y_cam
        if _project_y(y_draw + ry, zrel) >= _project_y(shadow, zrel):
            return True
    return False


# --------------------------------------------------------------- the model
@dataclass
class Ship:
    x: int = LAUNCHPAD_SIZE // 2
    y: int = LAUNCHPAD_Y
    z: int = LAUNCHPAD_SIZE // 2
    vx: int = 0
    vy: int = 0
    vz: int = 0
    pitch: int = 1                 # shipPitch (angle a)
    direction: int = 0             # shipDirection (angle b)
    fuel: int = INITIAL_FUEL
    gravity: int = GRAVITY_LEVELS[0]
    exhaust: tuple = (0, 0, 0)     # roof vector of last frame (for particles)
    alive: bool = True
    landed: bool = False


@dataclass
class Inputs:
    mouse_x: int = 511             # OS_Mouse coords; reset to (511,511)
    mouse_y: int = 511             # RISC OS y increases UP the screen
    buttons: int = 0               # BTN_THRUST | BTN_HOVER | BTN_FIRE


def object_at(tile_x, tile_z):
    """Object map hook (objectMap[z][x]); 1..11 = solid object. None here."""
    return 0xFF


def step(s: Ship, inp: Inputs):
    """One main-loop iteration of the player. Returns list of event strings."""
    ev = []
    if not s.alive:
        return ev
    burn = inp.buttons & 7                          # fuelBurnRate
    if s.fuel == 0:
        burn = 0

    # ---- part 1: mouse -> polar -> damped pitch/direction -> matrix
    mx = inp.mouse_x & M32
    if mx >= 1024:                                  # unsigned cap 0..1023
        mx = 1023
    mx = s32(mx - 512)
    my = s32(1024 - inp.mouse_y - 512)              # +ve = mouse moved down
    dist, ang = mouse_polar(s32(mx << 22), s32(my << 22))
    if (dist & M32) >= 0x40000000:
        dist = 0x3FFFFFFF
    dist <<= 1                                      # 0 .. &7FFFFFFE

    r4 = s32(s.direction - ang)                     # shortest way round
    if r4 >= 0:
        r4 = min(r4, ANGLE_STEP_CAP)
    elif r4 < -ANGLE_STEP_CAP:
        r4 = -ANGLE_STEP_CAP - 1
    r5 = s32(s.pitch - dist)
    if r5 > 0:
        r5 = min(r5, ANGLE_STEP_CAP)
    elif r5 < -ANGLE_STEP_CAP:
        r5 = -ANGLE_STEP_CAP - 1
    s.pitch = s32(s.pitch - (r5 >> 1))              # halfway to target
    s.direction = s32(s.direction - (r4 >> 1))
    m = rotation_matrix(s.pitch, s.direction)

    # ---- part 2: velocity / position
    if s.y < -HIGHEST_ALTITUDE:                     # too high: engines cut
        burn &= ~(BTN_THRUST | BTN_HOVER)
    ex, ey, ez = m['xRoof'], m['yRoof'], m['zRoof']
    full = burn & BTN_THRUST
    vx = s.vx - asr(s.vx, 6)                        # friction 1/64
    vy = s.vy - asr(s.vy, 6)
    vz = s.vz - asr(s.vz, 6)
    if full:                                        # full thrust = roof/2048
        vx -= asr(ex, 11); vy -= asr(ey, 11); vz -= asr(ez, 11)
    s.x = s32(s.x + vx); s.y = s32(s.y + vy); s.z = s32(s.z + vz)
    if burn & BTN_HOVER:                            # hover = roof/8192, AFTER
        vx -= asr(ex, 13); vy -= asr(ey, 13); vz -= asr(ez, 13)  # the move
    vy += s.gravity                                 # gravity (y is down)
    s.vx, s.vy, s.vz = s32(vx), s32(vy), s32(vz)
    s.exhaust = (ex, ey, ez)

    # ---- part 3: ground / object / launchpad
    s.landed = False
    safe_y = landscape_altitude(s.x, s.z) - UNDERCARRIAGE_Y
    if ((safe_y - s.y) & M32) < SAFE_HEIGHT:        # unsigned, as in source
        o = object_at((s.x & M32) >> 24, (s.z & M32) >> 24)
        if 0 < o < 12:
            s.alive = False
            ev.append('crash:object')
            return ev
    if s.y > safe_y:                                # LandOnLaunchpad
        if (s.x & M32) >= LAUNCHPAD_SIZE or (s.z & M32) >= LAUNCHPAD_SIZE:
            s.alive = False
            ev.append('crash:ground')
            return ev
        if abs(s.vx) + abs(s.vy) + abs(s.vz) < LANDING_SPEED:
            s.y = LAUNCHPAD_Y
            s.vx = s.vy = s.vz = 0
            if s.fuel + FUEL_REFUEL_STEP < FUEL_REFUEL_LIMIT:
                s.fuel += FUEL_REFUEL_STEP
            s.landed = True
            ev.append('landed')
        # too fast over the pad: no action here; the shadow test below
        # catches the ship once a vertex reaches the pad surface
    if vertex_below_shadow(s, m):
        s.alive = False
        ev.append('crash:vertex')
        return ev

    # ---- DrawFuelLevel (later in the same main-loop iteration)
    s.fuel = max(0, s.fuel - burn)   # NB subtracts the whole byte, incl. fire
    return ev


def gravity_for_score(score):
    """PrintCurrentScore: gravity rises with score."""
    if score >= 1488:
        return GRAVITY_LEVELS[2]
    if score >= 1024:
        return GRAVITY_LEVELS[1]
    return GRAVITY_LEVELS[0]


# --------------------------------------------------------------------- demo
def _t(v):
    return v / TILE_SIZE


def autopilot(s, frame):
    """Toy controller for the demo: hop up, drift off the pad, fly back, land.
    Mouse y: RISC OS y grows UP; moving the mouse up makes the ship fly into
    the screen (+z), right makes it fly right (+x)."""
    if frame < 8:                        # short burst of full thrust
        return Inputs(511, 511, BTN_THRUST)
    if frame < 60:                       # tilt towards +x and hover
        return Inputs(511 + 50, 511, BTN_HOVER)
    tx = tz = LAUNCHPAD_SIZE // 2
    ex = (tx - s.x) / TILE_SIZE - 15 * s.vx / TILE_SIZE
    ez = (tz - s.z) / TILE_SIZE - 15 * s.vz / TILE_SIZE
    # NB: offsets under ~32 counts give zero pitch (sqrt-table dead zone)
    def off(e):
        return 0 if abs(e) < 0.15 else int(math.copysign(min(110, 35 + 25 * abs(e)), e))
    mx, my = 511 + off(ex), 511 + off(ez)
    height = (LAUNCHPAD_Y - s.y) / TILE_SIZE       # tiles above resting y
    near = abs((tx - s.x) / TILE_SIZE) < 1 and abs((tz - s.z) / TILE_SIZE) < 1
    target = 0.0 if near else 3.0                  # hold 3 tiles up until over pad
    want_vy = max(-0.05, min(0.06, 0.04 * (height - target) + 0.01))   # +ve = down
    vy = s.vy / TILE_SIZE
    if vy > want_vy + 0.02:
        b = BTN_THRUST
    elif vy > want_vy:
        b = BTN_HOVER
    else:
        b = 0
    return Inputs(mx, my, b)


def demo(frames=700, every=20):
    s = Ship()
    print("frame   x(t)    y(t)  z(t)   vx      vy      vz    pitch  dir  "
          "fuel  ground  event")
    for f in range(frames):
        inp = autopilot(s, f)
        ev = step(s, inp)
        if f % every == 0 or ev and ev != ['landed'] or (ev and f > 100):
            g = landscape_altitude(s.x, s.z)
            print("%4d %7.3f %7.3f %6.3f %+7.4f %+7.4f %+7.4f %6.1f %5.1f %5d %6.2f  %s"
                  % (f, _t(s.x), _t(s.y), _t(s.z), _t(s.vx), _t(s.vy), _t(s.vz),
                     s.pitch * 360 / 2**32, s.direction * 360 / 2**32, s.fuel,
                     _t(g), ' '.join(ev)))
        if not s.alive or (ev == ['landed'] and f > 100):
            break
    return s


def selftest():
    # multiply: 0.5 * 0.5 = 0.25 (8-bit multiplier is exact here)
    assert mul_lander(1 << 30, 1 << 30) == 1 << 29
    # polar: mouse straight right 256 counts -> angle 0, distance r/2
    d, a = mouse_polar(256 << 22, 0)
    assert a == 0 and abs(d - (1 << 29)) < (1 << 22), (d, a)
    d, a = mouse_polar(0, 256 << 22)           # mouse down -> 90 degrees
    assert abs(a - (1 << 30)) < (1 << 24), a
    d, a = mouse_polar(-100 << 22, -100 << 22)  # up-left -> 225 degrees
    assert abs((a & M32) - 5 * (1 << 29)) < (1 << 25), a
    # matrix at a=b=0 ~ identity; products lose ~1/256 (8-bit multiplier)
    m = rotation_matrix(0, 0)
    assert m['yRoof'] > 0x7FFFFF00 and m['xNose'] == 0x7F7FFFFC
    # pad altitude and resting position
    assert landscape_altitude(LAUNCHPAD_SIZE // 2, LAUNCHPAD_SIZE // 2) == LAUNCHPAD_ALTITUDE
    s = Ship()
    n = 0
    for _ in range(50):                        # sitting on pad stays put:
        ev = step(s, Inputs())                 # gravity pushes it under the
        assert s.alive, ev                     # pad every other frame and
        n += 'landed' in ev                    # LandOnLaunchpad snaps it back
    assert n >= 24 and abs(s.y - LAUNCHPAD_Y) <= GRAVITY_LEVELS[0], (n, s.y)
    # free fall from rest tends to terminal velocity 64*g under 1/64 drag
    # (y is a 32-bit value: the world is only +/-128 tiles high)
    s = Ship(y=-120 * TILE_SIZE, x=-100 * TILE_SIZE)
    vmax = 0
    for _ in range(300):
        step(s, Inputs())
        if not s.alive:
            break
        vmax = s.vy
    vterm = vmax
    # too-fast arrival over the pad: LandOnLaunchpad declines, then the
    # vertex/shadow test fires; any arrival off the pad is a ground crash
    s = Ship(y=0, vy=TILE_SIZE // 4)
    evs = []
    while s.alive:
        evs += step(s, Inputs())
    assert evs[-1] == 'crash:vertex', evs
    s = Ship(x=20 * TILE_SIZE, y=0, vy=TILE_SIZE // 64)
    evs = []
    while s.alive:
        evs += step(s, Inputs())
    assert evs[-1] in ('crash:ground', 'crash:vertex'), evs
    print("crash tests:", evs[-1], "(off pad)")
    print("selftest ok; fall speed after %d frames %.3f tiles/frame "
          "(terminal 64*g = %.3f)" % (_, _t(vterm), _t(GRAVITY_LEVELS[0] * 64)))


# ================================================== 6502-friendly variant
# A sketch of the same model in 8/16/24-bit quantities (see NOTES.md):
#   angles      bytes, 256 = full circle (Lander: 2^32)
#   unit vecs   signed bytes, 127 ~ 1.0   (Lander: 2^31)
#   velocity    signed 16-bit, 1 = 2^-15 tile/frame  (= Lander >> 9)
#   position    24-bit, 1 = 2^-15 tile (8 bits tile + 15 bits fraction... we
#               keep 2^15/tile so x,z wrap at 512 tiles; y range +/-256 tiles)
#   input       a "virtual mouse" (sx, sy) in signed bytes nudged by keys,
#               1 unit = 4 Lander mouse counts, so pitch(byte) = |(sx,sy)|
# Only the roof (thrust) vector is needed for physics: 2 multiplies/frame.
LITE_TILE = 1 << 15
LITE_G = GRAVITY_LEVELS[0] >> 9          # 384
LITE_FULL_SHIFT = 4                      # 127 << 4 = 2032 ~ 2^20 >> 9 = 2048
LITE_HOVER_SHIFT = 2                     # 127 << 2 = 508  ~ 2^18 >> 9 = 512
LITE_LANDING = LANDING_SPEED >> 9        # 4096
LITE_UNDERCARRIAGE = UNDERCARRIAGE_Y >> 9
SIN8 = [int(round(127 * math.sin(2 * math.pi * i / 256))) for i in range(256)]


def atan2_8(y, x):
    """256-unit atan2; on a 6502 = octant fold + 32-entry table of atan(n/32)."""
    return int(round(math.atan2(y, x) * 128 / math.pi)) & 255


def mul8(a, b):
    """signed 8x8 -> (a*b) >> 7, i.e. a quarter-square table multiply."""
    return (a * b) >> 7


@dataclass
class LiteShip:
    x: int = 4 * LITE_TILE
    y: int = LAUNCHPAD_Y >> 9
    z: int = 4 * LITE_TILE
    vx: int = 0
    vy: int = 0
    vz: int = 0
    pitch: int = 0                 # 0..127 (0..180 degrees)
    direction: int = 0             # 0..255
    fuel: int = INITIAL_FUEL
    alive: bool = True


def step_lite(s, sx, sy, buttons, ground_y):
    """sx, sy: virtual-mouse offset (sy > 0 = 'mouse pulled back' = towards
    the viewer); ground_y(x, z) -> ground y in lite units (y down)."""
    ev = []
    burn = buttons & 7 if s.fuel else 0
    # orientation: target from the virtual mouse, then halve the error
    tdir = atan2_8(sy, sx)
    tpitch = min(127, int(math.isqrt(sx * sx + sy * sy)))   # table on a 6502
    ddir = ((s.direction - tdir + 128) & 255) - 128          # shortest way
    ddir = max(-48, min(48, ddir))                            # 0x30000000 cap
    dp = max(-48, min(48, s.pitch - tpitch))
    s.direction = (s.direction - (ddir >> 1)) & 255
    s.pitch -= dp >> 1
    sa, ca = SIN8[s.pitch & 255], SIN8[(s.pitch + 64) & 255]
    sb, cb = SIN8[s.direction], SIN8[(s.direction + 64) & 255]
    ex, ey, ez = -mul8(sa, cb), ca, mul8(sa, sb)               # roof vector
    if s.y < -(HIGHEST_ALTITUDE >> 9):
        burn &= ~(BTN_THRUST | BTN_HOVER)
    vx, vy, vz = s.vx - (s.vx >> 6), s.vy - (s.vy >> 6), s.vz - (s.vz >> 6)
    if burn & BTN_THRUST:
        vx -= ex << LITE_FULL_SHIFT; vy -= ey << LITE_FULL_SHIFT; vz -= ez << LITE_FULL_SHIFT
    s.x += vx; s.y += vy; s.z += vz
    if burn & BTN_HOVER:
        vx -= ex << LITE_HOVER_SHIFT; vy -= ey << LITE_HOVER_SHIFT; vz -= ez << LITE_HOVER_SHIFT
    vy += LITE_G
    s.vx, s.vy, s.vz = vx, vy, vz
    # landing / crash: centre test + lowest-vertex test. The y row of the
    # rotation matrix is (sin a, cos a, 0), so a vertex's height offset is
    # sin(a)*vx + cos(a)*vy -- two multiplies, and only for the 4 lowest
    # vertices (0, 1, 3, 5 cover every pitch/direction).
    g = ground_y(s.x, s.z)
    on_pad = 0 <= s.x < 8 * LITE_TILE and 0 <= s.z < 8 * LITE_TILE
    if s.y + LITE_UNDERCARRIAGE > g:
        if not on_pad:
            s.alive = False
            return ev + ['crash:ground']
        if abs(s.vx) + abs(s.vy) + abs(s.vz) < LITE_LANDING:
            s.y = g - LITE_UNDERCARRIAGE
            s.vx = s.vy = s.vz = 0
            s.fuel = min(FUEL_REFUEL_LIMIT - 1, s.fuel + FUEL_REFUEL_STEP)
            ev.append('landed')
    low = max(mul8(sa, v[0] >> 17) + mul8(ca, v[1] >> 17)
              for v in (SHIP_VERTICES[i] for i in (0, 1, 3, 5)))  # 2^-7 tile
    if s.y + (low << 8) >= g:
        s.alive = False
        return ev + ['crash:vertex']
    s.fuel = max(0, s.fuel - burn)
    return ev


def compare_demo(frames=160, every=20):
    """Run the full model (mouse) and the lite model (virtual mouse) on the
    same scripted input and print both trajectories (tiles)."""
    full, lite = Ship(), LiteShip()

    def script(f):          # (sx, sy, buttons): hop, tilt right, tilt back
        if f < 10:
            return 0, 0, BTN_THRUST
        if f < 70:
            return 20, 0, BTN_HOVER
        if f < 110:
            return -14, 14, BTN_HOVER | (BTN_THRUST if f % 4 == 0 else 0)
        return 0, 0, BTN_HOVER

    print("\nfull model vs 6502-lite model, same input (tiles)")
    print("frame   full x     y      z    |  lite x     y      z")
    for f in range(frames):
        sx, sy, b = script(f)
        step(full, Inputs(512 + 4 * sx, 512 - 4 * sy, b))
        step_lite(lite, sx, sy, b,
                  lambda x, z: landscape_altitude(x << 9, z << 9) >> 9)
        if f % every == 0 or f == frames - 1:
            print("%4d  %7.3f %7.3f %6.3f | %7.3f %7.3f %6.3f" % (
                f, _t(full.x), _t(full.y), _t(full.z),
                lite.x / LITE_TILE, lite.y / LITE_TILE, lite.z / LITE_TILE))


if __name__ == '__main__':
    selftest()
    demo()
    compare_demo()
