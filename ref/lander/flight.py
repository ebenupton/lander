#!/usr/bin/env python3
"""Lander's flight model, transcribed from Lander.arm (Mark Moxon's reconstruction
of David Braben's Lander, Acorn Archimedes, 1987: https://lander.bbcelite.com,
github.com/markmoxon/lander-source-code-acorn-archimedes).

step() is one main-loop iteration of the player's ship:
    MoveAndDrawPlayer part 1   mouse -> polar -> damped pitch and direction -> matrix
    MoveAndDrawPlayer part 2   drag, thrust, integration, gravity
    MoveAndDrawPlayer part 3   object collision; LandOnLaunchpad
    DrawObject part 2          the crash test (a vertex on or below its shadow)
    DrawFuelLevel              the fuel burn
with GetMouseInPolarCoordinates, CalculateRotationMatrix, MultiplyVectorByMatrix
and GetDotProduct (the shift-and-add multiply), GetLandscapeAltitude,
GetLandscapeBelowVertex, ProjectVertexOntoScreen (its main case), and the initial
values from StartNewGame, PlacePlayerOnLaunchpad and PrintCurrentScore (gravity
by score).  Bullets, exhaust particles and the object map are not transcribed.

Units are Lander's, 32-bit two's complement:
    position     TILE_SIZE = 2^24 a tile; x right, y down (altitude is -y), z into
                 the screen; the launchpad is 0 <= x, z < 8 tiles
    velocity     the same, a main-loop iteration (a frame)
    angle        2^32 a circle (2^30 = 90 degrees); the sine table has 1024 entries
    unit vector  2^31 = 1.0 (sinTable[n] = (2^31 - 1) sin(2 pi n / 1024))
Lander's multiplies keep only bits 30..23 of one operand; mul_lander() reproduces
them.  The tables are generated from the formulas in Lander.arm's comments; they
differ from its EQUDs by at most 3 (sine) and 1 (arctan, square root) in 2^31.

The game: src/game.s follows this model with the constants scaled for one step a
frame at 10 frames a second (see its header).  Nothing imports this file; run it
for the self-test.
"""
import math
from dataclasses import dataclass

from ship import VERTICES as SHIP_VERTICES

# Lander.arm's configuration constants.
TILE_SIZE = 0x01000000
LAUNCHPAD_ALTITUDE = 0x03500000
SEA_LEVEL = 0x05500000
LANDING_SPEED = 0x00200000          # |vx| + |vy| + |vz| must be below this to land
UNDERCARRIAGE_Y = 0x00640000        # ship's centre to its bottom: 0.390625 tiles
LAUNCHPAD_Y = LAUNCHPAD_ALTITUDE - UNDERCARRIAGE_Y
LAUNCHPAD_SIZE = TILE_SIZE * 8
HIGHEST_ALTITUDE = TILE_SIZE * 52   # engines cut when y < -this
SAFE_HEIGHT = TILE_SIZE * 3 // 2    # objects are checked for within this of the ground
LAND_MID_HEIGHT = TILE_SIZE * 5
TILES_Z = 11
CAMERA_PLAYER_Z = (TILES_Z - 6) * TILE_SIZE                # 5 tiles
LANDSCAPE_Z = TILE_SIZE * (TILES_Z - 1) + 10 * TILE_SIZE   # 20 tiles
LANDSCAPE_Z_MID = LANDSCAPE_Z - CAMERA_PLAYER_Z            # 15 tiles: the ship's depth

GRAVITY_LEVELS = (0x30000, 0x50000, 0x70000)  # score < 1024, >= 1024, >= 1488
INITIAL_FUEL = 3413                 # initialFuelLevel
FUEL_REFUEL_STEP = 0x20             # a frame, sat on the pad
FUEL_REFUEL_LIMIT = 0x1400          # stored only while the result is below this
ANGLE_STEP_CAP = 0x30000000         # the attitude error used a frame: 67.5 degrees

BTN_FIRE, BTN_HOVER, BTN_THRUST = 1, 2, 4   # OS_Mouse buttons %lmr

M32 = 0xFFFFFFFF


def s32(v):
    """The 32-bit word v as a signed integer."""
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v


def asr(v, n):
    """v ASR n."""
    return s32(v) >> n


# sinTable, arctanTable and squareRootTable, from the formulas in their headers.
SIN = [int((2**31 - 1) * math.sin(2 * math.pi * i / 1024)) for i in range(1024)]
ATAN = [int((2**31 - 1) / math.pi * math.atan(i / 128)) for i in range(128)]
SQRT = [int((2**31 - 1) * math.sqrt(i / 1024)) for i in range(1024)]


def sin32(angle):
    """sinTable[angle >> 22]: Lander's LDR by angle LSR #20 with bits 20 and 21
    cleared."""
    return SIN[(angle & M32) >> 22]


def cos32(angle):
    """sin32 of the angle plus a quarter turn."""
    return sin32(angle + 0x40000000)


def mul_lander(a, b):
    """Lander's shift-and-add multiply (CalculateRotationMatrix rmat1..4,
    GetDotProduct dotp1..3): a * b / 2^31 with the sign of a * b, |a| truncated to
    its bits 30..23 (eight bits) and |b| at full precision."""
    neg = (s32(a) < 0) != (s32(b) < 0)
    A = abs(s32(a)) & M32
    B = abs(s32(b)) & M32
    carry = (A >> 30) & 1                     # MOVS R2, R2, LSL #2: C = bit 30
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
    """GetMouseInPolarCoordinates pole5 and pole6: x * x / 2^32 for x >= 0, the
    multiplier truncated to bits 31..24 of x."""
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
    """GetMouseInPolarCoordinates pole1 and pole3: the eight-step restoring
    division of n by d, n <= d: floor(256 n / d), 255 at most."""
    if d == 0:
        return 255
    return min(255, (n << 8) // d)


def mouse_polar(mx, my):
    """GetMouseInPolarCoordinates: (distance, angle) of the scaled mouse offset
    (mx, my), each a count << 22.  The angle is atan2(my, mx) with 2^32 a circle:
    the smaller magnitude over the larger through _div8, arctanTable[q >> 1], and
    the octant folded back in units of 2^29 (45 degrees).  The distance is
    squareRootTable[(mx^2 + my^2) / 2^54], about half the offset's length in the
    inputs' scale; it is zero while the offset is under 32 counts."""
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
    """CalculateRotationMatrix(a = shipPitch, b = shipDirection): the nine entries
    (1.0 = 2^31) by Lander's names,
        nose = ( cos a cos b,  sin a, -cos a sin b)    model +x
        roof = (-sin a cos b,  cos a,  sin a sin b)    model +y: the thrust axis
        side = ( sin b,        0,      cos b)          model +z
    the products by mul_lander with Lander's choice of truncated operand."""
    sa, sb, ca, cb = sin32(a), sin32(b), cos32(a), cos32(b)
    return dict(
        xNose=mul_lander(ca, cb), yNose=sa, zNose=-mul_lander(sb, ca),
        xRoof=-mul_lander(sa, cb), yRoof=ca, zRoof=mul_lander(sa, sb),
        xSide=sb, ySide=0, zSide=cb)


def rotate(m, v):
    """MultiplyVectorByMatrix: v.x nose + v.y roof + v.z side, each product by
    mul_lander with the matrix entry as the truncated operand."""
    x, y, z = v
    return (s32(mul_lander(m['xNose'], x) + mul_lander(m['xRoof'], y) + mul_lander(m['xSide'], z)),
            s32(mul_lander(m['yNose'], x) + mul_lander(m['yRoof'], y) + mul_lander(m['ySide'], z)),
            s32(mul_lander(m['zNose'], x) + mul_lander(m['zRoof'], y) + mul_lander(m['zSide'], z)))


def landscape_altitude(x, z):
    """GetLandscapeAltitude: the ground's y at (x, z), LAND_MID_HEIGHT less six
    sines of the coordinates (four scaled 1/128, two 1/256: +-5 tiles in all),
    no lower than SEA_LEVEL (y is down), and LAUNCHPAD_ALTITUDE over the pad
    (0 <= x, z < 8 tiles, unsigned)."""
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


def _project_y(y, z):
    """ProjectVertexOntoScreen's screen row for a camera-relative (y, z) with
    |y| <= z: 64 +- floor(256 |y| / z)."""
    q = ((abs(y) << 9) // z) >> 1
    return 64 + q if y >= 0 else 64 - q


def vertex_below_shadow(state, m):
    """DrawObject part 2's crash test.  The ship is drawn at camera-relative
    (0, max(y, 0), LANDSCAPE_Z_MID) with the camera's y at min(y, 0); each vertex
    is projected, and so is the point on the ground below it
    (GetLandscapeBelowVertex).  crashedFlag is set if any vertex's screen row is
    at or below its shadow's: the vertex is on or under the ground to within a
    pixel row (about 0.06 tiles at the ship's depth).  Both rows are within the
    screen here, so Lander's unsigned compare is an ordinary one."""
    y_cam = min(state.y, 0)
    y_draw = max(state.y, 0)
    for v in SHIP_VERTICES:
        rx, ry, rz = rotate(m, v)
        zrel = LANDSCAPE_Z_MID + rz
        wx, wz = s32(state.x + rx), s32(state.z + rz)
        shadow = landscape_altitude(wx, wz) - y_cam
        if _project_y(y_draw + ry, zrel) >= _project_y(shadow, zrel):
            return True
    return False


@dataclass
class Ship:
    """The player's state: xPlayer.. zVelocity, shipPitch, shipDirection,
    fuelLevel, gravity and the last roof vector (xExhaust), with the start values
    of PlacePlayerOnLaunchpad and StartNewGame."""
    x: int = LAUNCHPAD_SIZE // 2
    y: int = LAUNCHPAD_Y
    z: int = LAUNCHPAD_SIZE // 2
    vx: int = 0
    vy: int = 0
    vz: int = 0
    pitch: int = 1
    direction: int = 0
    fuel: int = INITIAL_FUEL
    gravity: int = GRAVITY_LEVELS[0]
    exhaust: tuple = (0, 0, 0)
    alive: bool = True
    landed: bool = False


@dataclass
class Inputs:
    """OS_Mouse: the pointer (y up the screen; ResetMousePosition puts it at
    (511, 511)) and the buttons, BTN_THRUST (left), BTN_HOVER (middle),
    BTN_FIRE (right)."""
    mouse_x: int = 511
    mouse_y: int = 511
    buttons: int = 0


def object_at(tile_x, tile_z):
    """objectMap[tile_z][tile_x]: 1..11 is an object the ship can hit.  The map is
    not transcribed; every tile is empty (&FF)."""
    return 0xFF


def step(s: Ship, inp: Inputs):
    """One main-loop iteration of the player's ship.  Returns the events:
    'landed', or one of 'crash:object', 'crash:ground', 'crash:vertex', after
    which s.alive is False and further steps do nothing."""
    ev = []
    if not s.alive:
        return ev
    burn = inp.buttons & 7                          # fuelBurnRate
    if s.fuel == 0:
        burn = 0

    # MoveAndDrawPlayer part 1.  The mouse x is capped to 0..1023 (unsigned) and
    # offset to -512..511; y is reversed, so my > 0 is the mouse pulled towards
    # the player.  The polar distance, capped below &40000000 and doubled, is the
    # target pitch; the angle is the target direction.  Each moves halfway to its
    # target, the error first capped at ANGLE_STEP_CAP either way (the negative
    # cap is -&30000001).
    mx = inp.mouse_x & M32
    if mx >= 1024:
        mx = 1023
    mx = s32(mx - 512)
    my = s32(512 - inp.mouse_y)
    dist, ang = mouse_polar(s32(mx << 22), s32(my << 22))
    if (dist & M32) >= 0x40000000:
        dist = 0x3FFFFFFF
    dist <<= 1

    r4 = s32(s.direction - ang)                     # wraps: the shorter way round
    if r4 >= 0:
        r4 = min(r4, ANGLE_STEP_CAP)
    elif r4 < -ANGLE_STEP_CAP:
        r4 = -ANGLE_STEP_CAP - 1
    r5 = s32(s.pitch - dist)
    if r5 > 0:
        r5 = min(r5, ANGLE_STEP_CAP)
    elif r5 == 0 or r5 < -ANGLE_STEP_CAP:
        # BLE then CMN/MVNLO: a zero error takes the negative path and fails the
        # carry test, so it is replaced by the negative cap and the pitch kicks
        # by +&18000001.  At rest the pitch is 1 and the target 0, so this does
        # not arise there.
        r5 = -ANGLE_STEP_CAP - 1
    s.pitch = s32(s.pitch - (r5 >> 1))
    s.direction = s32(s.direction - (r4 >> 1))
    m = rotation_matrix(s.pitch, s.direction)

    # MoveAndDrawPlayer part 2.  Per axis: drag v -= v >> 6; full thrust (left
    # button) v -= roof >> 11; the position moves; hover (middle) v -= roof >> 13,
    # after the move; then gravity on vy.  Above HIGHEST_ALTITUDE both thrust bits
    # are cleared from the burn rate first.
    if s.y < -HIGHEST_ALTITUDE:
        burn &= ~(BTN_THRUST | BTN_HOVER)
    ex, ey, ez = m['xRoof'], m['yRoof'], m['zRoof']
    vx = s.vx - asr(s.vx, 6)
    vy = s.vy - asr(s.vy, 6)
    vz = s.vz - asr(s.vz, 6)
    if burn & BTN_THRUST:
        vx -= asr(ex, 11); vy -= asr(ey, 11); vz -= asr(ez, 11)
    s.x = s32(s.x + vx); s.y = s32(s.y + vy); s.z = s32(s.z + vz)
    if burn & BTN_HOVER:
        vx -= asr(ex, 13); vy -= asr(ey, 13); vz -= asr(ez, 13)
    vy += s.gravity
    s.vx, s.vy, s.vz = s32(vx), s32(vy), s32(vz)
    s.exhaust = (ex, ey, ez)

    # MoveAndDrawPlayer part 3.  safe_y is the ground under the ship less the
    # undercarriage.  Within SAFE_HEIGHT above it (an unsigned compare, so only
    # from above) an object on the ship's tile is a crash.  Below it,
    # LandOnLaunchpad: off the pad is a crash; on it and slow enough the ship is
    # set down (y = LAUNCHPAD_Y, velocity zero, refuelled); on it and too fast
    # nothing happens until a vertex reaches the pad.
    s.landed = False
    safe_y = landscape_altitude(s.x, s.z) - UNDERCARRIAGE_Y
    if ((safe_y - s.y) & M32) < SAFE_HEIGHT:
        o = object_at((s.x & M32) >> 24, (s.z & M32) >> 24)
        if 0 < o < 12:
            s.alive = False
            ev.append('crash:object')
            return ev
    if s.y > safe_y:
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
    if vertex_below_shadow(s, m):
        s.alive = False
        ev.append('crash:vertex')
        return ev

    # DrawFuelLevel, later in the same iteration: the whole burn-rate byte is
    # subtracted, so the fire button costs 1 a frame too.
    s.fuel = max(0, s.fuel - burn)
    return ev


def gravity_for_score(score):
    """PrintCurrentScore's gravity: &30000, &50000 from a score of 1024, &70000
    from 1488."""
    if score >= 1488:
        return GRAVITY_LEVELS[2]
    if score >= 1024:
        return GRAVITY_LEVELS[1]
    return GRAVITY_LEVELS[0]


def selftest():
    """Checks of the transcription's arithmetic and of the model's behaviour at
    rest, in free fall and arriving at the ground."""
    assert mul_lander(1 << 30, 1 << 30) == 1 << 29
    d, a = mouse_polar(256 << 22, 0)                # mouse right: angle 0, r/2
    assert a == 0 and abs(d - (1 << 29)) < (1 << 22), (d, a)
    d, a = mouse_polar(0, 256 << 22)                # mouse pulled back: 90 degrees
    assert abs(a - (1 << 30)) < (1 << 24), a
    d, a = mouse_polar(-100 << 22, -100 << 22)      # up and left: 225 degrees
    assert abs((a & M32) - 5 * (1 << 29)) < (1 << 25), a
    m = rotation_matrix(0, 0)                       # identity to 8 bits
    assert m['yRoof'] > 0x7FFFFF00 and m['xNose'] == 0x7F7FFFFC
    assert landscape_altitude(LAUNCHPAD_SIZE // 2, LAUNCHPAD_SIZE // 2) == LAUNCHPAD_ALTITUDE

    # At rest on the pad: gravity sinks the ship a step and LandOnLaunchpad
    # restores it, so 'landed' fires on alternate frames.
    s = Ship()
    n = 0
    for _ in range(50):
        ev = step(s, Inputs())
        assert s.alive, ev
        n += 'landed' in ev
    assert n >= 24 and abs(s.y - LAUNCHPAD_Y) <= GRAVITY_LEVELS[0], (n, s.y)

    # Free fall tends to 64 g a frame under the 1/64 drag.
    s = Ship(y=-120 * TILE_SIZE, x=-100 * TILE_SIZE)
    vmax = 0
    for i in range(300):
        step(s, Inputs())
        if not s.alive:
            break
        vmax = s.vy
    assert abs(vmax - 64 * GRAVITY_LEVELS[0]) < GRAVITY_LEVELS[0] * 4, vmax

    # Too fast over the pad: LandOnLaunchpad declines and the vertex test fires.
    s = Ship(y=0, vy=TILE_SIZE // 4)
    evs = []
    while s.alive:
        evs += step(s, Inputs())
    assert evs[-1] == 'crash:vertex', evs
    # Off the pad: any arrival is a crash.
    s = Ship(x=20 * TILE_SIZE, y=0, vy=TILE_SIZE // 64)
    evs = []
    while s.alive:
        evs += step(s, Inputs())
    assert evs[-1] in ('crash:ground', 'crash:vertex'), evs
    print("selftest ok")


if __name__ == '__main__':
    selftest()
