#!/usr/bin/env python3
"""
Lander (Acorn Archimedes, D. Braben 1987) -- player's ship blueprint.

Extracted verbatim from `objectPlayer` in Mark Moxon's reconstructed source
  https://lander.bbcelite.com/source/main/variable/objectplayer.html
  github.com/markmoxon/lander-source-code-acorn-archimedes
    1-source-files/main-sources/Lander.arm  (".objectPlayer")

Units / formats (all straight from the blueprint):
  * Vertex coords are signed 32-bit, 1 tile = &01000000 (2^24). So the values
    below in "tiles" are raw / 2^24.
  * Axes: x right, y DOWN (the whole game uses an inverted y-axis: altitude
    grows downwards), z into the screen. Model x = "nose" axis (the gun fires
    along +x, see MoveAndDrawPlayer part 5), model y = "roof" axis (exhaust /
    thrust axis, +y points out through the floor), model z = "side" axis.
  * Face normals are signed 32-bit with 1.0 = 2^31 (same scale as the sine
    table and the rotation matrix). They are pre-computed (not derived at
    runtime) and stored per face, followed by three vertex indices and a
    12-bit colour &rgb (4 bits per channel).
  * Blueprint flags = %11: bit 0 = rotates (apply rotation matrix), bit 1 =
    casts a shadow.

Run this file to write ship.json and ship.png (several views) next to it.
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def s32(v):
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


# ----- raw blueprint, copied as hex from Lander.arm (.objectPlayer) ---------
RAW_VERTICES = [            # xObject,   yObject,   zObject
    (0x01000000, 0x00500000, 0x00800000),   # 0
    (0x01000000, 0x00500000, 0xFF800000),   # 1
    (0x00000000, 0x000A0000, 0xFECCCCCD),   # 2
    (0xFF19999A, 0x00500000, 0x00000000),   # 3
    (0x00000000, 0x000A0000, 0x01333333),   # 4
    (0xFFE66667, 0xFF880000, 0x00000000),   # 5
    (0x00555555, 0x00500000, 0x00400000),   # 6
    (0x00555555, 0x00500000, 0xFFC00000),   # 7
    (0xFFCCCCCD, 0x00500000, 0x00000000),   # 8
]

RAW_FACES = [  # xNormal,   yNormal,   zNormal,  v1, v2, v3, colour
    (0x457C441A, 0x9E2A1F4C, 0x00000000, 0, 1, 5, 0x080),  # 0
    (0x35F5D83B, 0x9BC03EC1, 0xDA12D71D, 1, 2, 5, 0x040),  # 1
    (0x35F5D83B, 0x9BC03EC1, 0x25ED28E3, 0, 5, 4, 0x040),  # 2
    (0xB123D51C, 0xAF3F50EE, 0xD7417278, 2, 3, 5, 0x040),  # 3
    (0xB123D51D, 0xAF3F50EE, 0x28BE8D88, 3, 4, 5, 0x040),  # 4
    (0xF765D8CD, 0x73242236, 0xDF4FD176, 1, 2, 3, 0x088),  # 5
    (0xF765D8CD, 0x73242236, 0x20B02E8A, 0, 3, 4, 0x088),  # 6
    (0x00000000, 0x78000000, 0x00000000, 0, 1, 3, 0x044),  # 7
    (0x00000000, 0x78000000, 0x00000000, 6, 7, 8, 0xC80),  # 8
]
FLAGS = 0b11
UNDERCARRIAGE_Y = 0x00640000   # 0.390625 tiles, centre -> bottom of ship

VERTICES = [tuple(s32(c) for c in v) for v in RAW_VERTICES]
FACES = [dict(normal=tuple(s32(c) for c in f[:3]), verts=f[3:6], colour=f[6])
         for f in RAW_FACES]

TILE = 1 << 24
ONE = 1 << 31


def vertices_tiles():
    return [tuple(c / TILE for c in v) for v in VERTICES]


# ----- Lander's shading rule (DrawObject part 5) ----------------------------
def lander_brightness(nx, ny):
    """nx, ny = ROTATED normal (32-bit, 1.0 = 2^31). Returns 0..11.
    R1 = ((&80000000 - ny) mod 2^32) >> 28 ; +1 if nx < 0 ; max(0, R1 - 5)
    (light from above and slightly left; y is down so ny<0 = facing up)."""
    r1 = ((0x80000000 - ny) & 0xFFFFFFFF) >> 28
    if nx < 0:
        r1 += 1
    return max(0, r1 - 5)


def lander_face_rgb(colour, bright):
    """&rgb (4-bit/channel) + brightness on each channel, clipped to 15.
    (Lander then packs this into a VIDC 256-colour byte, losing some bits;
    here we just expand 4 bits -> 8 bits for display.)"""
    r = min(15, (colour >> 8 & 15) + bright)
    g = min(15, (colour >> 4 & 15) + bright)
    b = min(15, (colour & 15) + bright)
    return (r * 17, g * 17, b * 17)


# ----- float rotation matrix as built by CalculateRotationMatrix -----------
def rotation_matrix(a, b):
    """a = shipPitch, b = shipDirection (radians). Columns = nose, roof, side.
       [ cos a cos b   -sin a cos b   sin b ]
       [ sin a          cos a         0     ]
       [ -cos a sin b   sin a sin b   cos b ]"""
    ca, sa, cb, sb = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
    return [[ca * cb, -sa * cb, sb],
            [sa, ca, 0.0],
            [-ca * sb, sa * sb, cb]]


def mat_vec(m, v):
    return tuple(sum(m[r][c] * v[c] for c in range(3)) for r in range(3))


def check_data():
    """Sanity checks: normal lengths, normal vs winding, normal vs outward."""
    vt = vertices_tiles()
    cen = [sum(v[i] for v in vt) / len(vt) for i in range(3)]
    out = []
    for i, f in enumerate(FACES):
        n = [c / ONE for c in f['normal']]
        ln = math.sqrt(sum(c * c for c in n))
        p0, p1, p2 = (vt[k] for k in f['verts'])
        e1 = [p1[j] - p0[j] for j in range(3)]
        e2 = [p2[j] - p0[j] for j in range(3)]
        cr = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2],
              e1[0] * e2[1] - e1[1] * e2[0]]
        lc = math.sqrt(sum(c * c for c in cr)) or 1
        cosang = sum(n[j] * cr[j] for j in range(3)) / (ln * lc) if ln else 0
        fc = [(p0[j] + p1[j] + p2[j]) / 3 for j in range(3)]
        outward = sum(n[j] * (fc[j] - cen[j]) for j in range(3))
        out.append((i, ln, cosang, outward))
    return out


# ----- renderer --------------------------------------------------------------
def render_view(draw, ox, oy, size, a, b, label, cam_dist=3.2, font=None,
                faithful=True):
    """Perspective view with the ship at (0,0,cam_dist) tiles from a camera
    looking along +z (as in Lander: screen = centre + f*x/z, f*y/z, y down).
    faithful=True: back-face cull with Lander's test (normal . object-centre
    vector < 0), draw visible faces in BLUEPRINT ORDER (no per-face sort,
    exactly as DrawObject does), then wireframe overlay."""
    m = rotation_matrix(a, b)
    f = size * 0.9
    cx, cy = ox + size / 2, oy + size / 2
    obj = (0.0, 0.0, cam_dist)
    pts = []
    for v in vertices_tiles():
        r = mat_vec(m, v)
        w = (r[0] + obj[0], r[1] + obj[1], r[2] + obj[2])
        pts.append((cx + f * w[0] / w[2], cy + f * w[1] / w[2]))
    draw.rectangle([ox, oy, ox + size - 1, oy + size - 1], outline=(60, 60, 60))
    visible = []
    for i, fc in enumerate(FACES):
        n = mat_vec(m, [c / ONE for c in fc['normal']])
        vis = sum(n[j] * obj[j] for j in range(3)) < 0   # Lander's test
        visible.append(vis)
        if not vis:
            continue
        nr = [int(c * ONE) for c in n]
        br = lander_brightness(nr[0], nr[1])
        poly = [pts[k] for k in fc['verts']]
        draw.polygon(poly, fill=lander_face_rgb(fc['colour'], br))
    # hidden edges dim dashed-grey first, then edges of visible faces white
    for want, col in ((False, (70, 70, 90)), (True, (255, 255, 255))):
        for fc, vis in zip(FACES, visible):
            if vis != want:
                continue
            vs = fc['verts']
            for k in range(3):
                draw.line([pts[vs[k]], pts[vs[(k + 1) % 3]]], fill=col)
    for k, p in enumerate(pts):
        draw.text((p[0] + 2, p[1] - 10), str(k), fill=(255, 255, 0), font=font)
    draw.text((ox + 4, oy + 4), label, fill=(200, 200, 200), font=font)


def render_ortho(draw, ox, oy, size, axes, label, font=None):
    """Orthographic wireframe; axes = (i, j) model axes for screen x, y."""
    vt = vertices_tiles()
    s = size / 3.0
    cx, cy = ox + size / 2, oy + size / 2
    pts = [(cx + v[axes[0]] * s, cy + v[axes[1]] * s) for v in vt]
    draw.rectangle([ox, oy, ox + size - 1, oy + size - 1], outline=(60, 60, 60))
    for fc in FACES:
        vs = fc['verts']
        for k in range(3):
            draw.line([pts[vs[k]], pts[vs[(k + 1) % 3]]], fill=(120, 200, 255))
    for k, p in enumerate(pts):
        draw.text((p[0] + 2, p[1] - 10), str(k), fill=(255, 255, 0), font=font)
    draw.text((ox + 4, oy + 4), label, fill=(200, 200, 200), font=font)


def main():
    from PIL import Image, ImageDraw
    data = dict(
        source="Lander.arm .objectPlayer (lander.bbcelite.com/source/main/"
               "variable/objectplayer.html)",
        units=dict(vertex="signed 32-bit, 1 tile = 0x01000000; y axis DOWN",
                   normal="signed 32-bit, 1.0 = 0x80000000",
                   colour="12-bit &rgb, 4 bits per channel"),
        flags=FLAGS,
        flags_meaning="bit0=1 rotates, bit1=1 has shadow",
        undercarriage_y=UNDERCARRIAGE_Y,
        vertices_raw=[list(v) for v in VERTICES],
        vertices_hex=[["&%08X" % (c & 0xFFFFFFFF) for c in v]
                      for v in RAW_VERTICES],
        vertices_tiles=[[round(c, 6) for c in v] for v in vertices_tiles()],
        faces=[dict(index=i, verts=list(f['verts']),
                    normal_raw=list(f['normal']),
                    normal_hex=["&%08X" % (c & 0xFFFFFFFF) for c in RAW_FACES[i][:3]],
                    normal=[round(c / ONE, 6) for c in f['normal']],
                    colour="&%03X" % f['colour'])
               for i, f in enumerate(FACES)],
    )
    with open(os.path.join(HERE, 'ship.json'), 'w') as fp:
        json.dump(data, fp, indent=1)

    print("face  |n|    cos(n,winding)  n.(facecentre-centroid)")
    for i, ln, ca, ow in check_data():
        print("%2d   %.4f   %+.3f          %+.3f" % (i, ln, ca, ow))

    size = 300
    img = Image.new('RGB', (size * 4, size * 2), (0, 0, 0))
    d = ImageDraw.Draw(img)
    deg = math.pi / 180
    # In Lander the camera looks along +z and the ship is drawn 15 tiles
    # away; we bring it closer for a big picture. a = pitch, b = direction.
    views = [(0, 0, "a=0 b=0 (on pad)"),
             (30 * deg, 0, "a=30 b=0"),
             (30 * deg, 90 * deg, "a=30 b=90"),
             (60 * deg, -45 * deg, "a=60 b=-45"),
             (-25 * deg, 30 * deg, "a=-25 b=30"),
             (150 * deg, 0, "a=150 (underside)")]
    for k, (a, b, lab) in enumerate(views):
        render_view(d, (k % 4) * size, (k // 4) * size, size, a, b, lab)
    # Orthographic wireframes: top view (x right, z up-screen) and side view
    render_ortho(d, 2 * size, size, size, (0, 2), "ortho top: x->, z down")
    render_ortho(d, 3 * size, size, size, (0, 1), "ortho side: x->, y down")
    out = os.path.join(HERE, 'ship.png')
    img.save(out)
    print("wrote", out, "and ship.json")


if __name__ == '__main__':
    main()
