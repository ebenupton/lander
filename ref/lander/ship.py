#!/usr/bin/env python3
"""Lander's ship: the objectPlayer blueprint from Lander.arm, the rotation matrix,
back-face test and shading rule that DrawObject applies to it, and a PIL render.

Source: Mark Moxon's reconstruction of David Braben's Lander (Acorn Archimedes,
1987), https://lander.bbcelite.com and github.com/markmoxon/lander-source-code-
acorn-archimedes, file Lander.arm.  The routine names below are its.

Units (Lander's, 32-bit two's complement throughout):
    TILE = 2^24    a landscape tile; vertex coordinates are in these
    ONE  = 2^31    1.0 for unit vectors: normals, sines, matrix entries
Axes: x right, y down (altitude is -y), z into the screen.  In the model, +x is
the nose (the gun fires along it: MoveAndDrawPlayer part 5), +y points out
through the floor (the roof vector, the thrust axis: MoveAndDrawPlayer part 2),
+z is the side.

The game: tools/shipgen.py imports VERTICES, FACES, TILE, ONE, rotation_matrix,
mat_vec and lander_brightness to pre-rotate, pre-project and shade the ship for
every orientation the BBC draws.

Run as a script, this prints the blueprint checks (check_data) and writes ship.png
beside itself: six perspective views drawn as DrawObject would (Lander's cull,
blueprint-order fill and shading) with a wireframe over them, and two
orthographic wireframes.
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

TILE = 1 << 24
ONE = 1 << 31


def s32(v):
    """The 32-bit word v as a signed integer."""
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


# .objectPlayer, as the EQUDs in Lander.arm: nine vertices (xObject, yObject,
# zObject) and nine faces (xNormal, yNormal, zNormal, vertex1, vertex2, vertex3,
# colour).  Normals are stored, not derived at run time; colours are &rgb, four
# bits a channel.
RAW_VERTICES = [
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

RAW_FACES = [
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

# The blueprint's flags word: bit 0 set, the object rotates (MultiplyVectorByMatrix
# applies the rotation matrix); bit 1 set, it casts a shadow (DrawObject part 4).
FLAGS = 0b11

VERTICES = [tuple(s32(c) for c in v) for v in RAW_VERTICES]
FACES = [dict(normal=tuple(s32(c) for c in f[:3]), verts=f[3:6], colour=f[6])
         for f in RAW_FACES]


def vertices_tiles():
    """The vertices in tiles (floats)."""
    return [tuple(c / TILE for c in v) for v in VERTICES]


def lander_brightness(nx, ny):
    """DrawObject part 5's face brightness, 0..11, from the rotated normal's x and
    y (32-bit, ONE = 1.0): ((&80000000 - ny) mod 2^32) >> 28, plus 1 if nx < 0,
    less 5, floored at 0.  Faces towards -y (upwards) are brightest, and faces
    towards -x a step brighter: the light is above and to the left."""
    r1 = ((0x80000000 - ny) & 0xFFFFFFFF) >> 28
    if nx < 0:
        r1 += 1
    return max(0, r1 - 5)


def lander_face_rgb(colour, bright):
    """A face's colour (&rgb) with the brightness added to each channel and clipped
    at 15, as DrawObject part 5 does, widened to 8 bits a channel for display.
    (Lander then packs the channels into a VIDC byte, dropping their low bits.)"""
    r = min(15, (colour >> 8 & 15) + bright)
    g = min(15, (colour >> 4 & 15) + bright)
    b = min(15, (colour & 15) + bright)
    return (r * 17, g * 17, b * 17)


def rotation_matrix(a, b):
    """CalculateRotationMatrix in floats: a = shipPitch, b = shipDirection
    (radians).  The columns are the nose, roof and side vectors:
        [ cos a cos b   -sin a cos b   sin b ]
        [ sin a          cos a         0     ]
        [ -cos a sin b   sin a sin b   cos b ]
    so mat_vec(m, v) = v.x nose + v.y roof + v.z side."""
    ca, sa, cb, sb = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
    return [[ca * cb, -sa * cb, sb],
            [sa, ca, 0.0],
            [-ca * sb, sa * sb, cb]]


def mat_vec(m, v):
    """The 3x3 matrix m times the vector v."""
    return tuple(sum(m[r][c] * v[c] for c in range(3)) for r in range(3))


def check_data():
    """For each face: its normal's length, the cosine between the normal and the
    cross product of its edges (its winding), and the normal's component along
    the face centre from the vertex centroid (positive: outward)."""
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


def render_view(draw, ox, oy, size, a, b, label, cam_dist=3.2, font=None):
    """One perspective view in the size-pixel square at (ox, oy): the ship at
    pitch a, direction b, placed cam_dist tiles along +z from a camera looking
    along +z, projected as Lander does (centre + f x / z, centre + f y / z, y
    down).  Lander draws the ship 15 tiles out; nearer here for a larger picture.
    Faces are culled by Lander's test (DrawObject part 3: the rotated normal
    dotted with the object's position is negative), filled in blueprint order
    (DrawObject sorts nothing within an object) in Lander's shade, then the edges
    are drawn over: hidden faces' dim, visible faces' white, with the vertex
    numbers."""
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
        vis = sum(n[j] * obj[j] for j in range(3)) < 0
        visible.append(vis)
        if not vis:
            continue
        nr = [int(c * ONE) for c in n]
        br = lander_brightness(nr[0], nr[1])
        poly = [pts[k] for k in fc['verts']]
        draw.polygon(poly, fill=lander_face_rgb(fc['colour'], br))
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
    """An orthographic wireframe of the model in the size-pixel square at (ox, oy),
    model axes axes[0] and axes[1] along screen x and y, with the vertex numbers."""
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
    """Print check_data and write ship.png (4 x 2 views of 300 pixels) beside
    this file."""
    from PIL import Image, ImageDraw
    print("face  |n|    cos(n,winding)  n.(facecentre-centroid)")
    for i, ln, ca, ow in check_data():
        print("%2d   %.4f   %+.3f          %+.3f" % (i, ln, ca, ow))

    size = 300
    img = Image.new('RGB', (size * 4, size * 2), (0, 0, 0))
    d = ImageDraw.Draw(img)
    deg = math.pi / 180
    views = [(0, 0, "a=0 b=0 (on pad)"),
             (30 * deg, 0, "a=30 b=0"),
             (30 * deg, 90 * deg, "a=30 b=90"),
             (60 * deg, -45 * deg, "a=60 b=-45"),
             (-25 * deg, 30 * deg, "a=-25 b=30"),
             (150 * deg, 0, "a=150 (underside)")]
    for k, (a, b, lab) in enumerate(views):
        render_view(d, (k % 4) * size, (k // 4) * size, size, a, b, lab)
    render_ortho(d, 2 * size, size, size, (0, 2), "ortho top: x->, z down")
    render_ortho(d, 3 * size, size, size, (0, 1), "ortho side: x->, y down")
    out = os.path.join(HERE, 'ship.png')
    img.save(out)
    print("wrote", out)


if __name__ == '__main__':
    main()
