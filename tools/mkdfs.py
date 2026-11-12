#!/usr/bin/env python3
"""Write an Acorn DFS single-sided disc image (.ssd).

    python3 tools/mkdfs.py OUT.ssd TITLE NAME:PATH[:LOAD[:EXEC]] ...

The image: 80 tracks of 10 sectors of 256 bytes, the catalogue in sectors 0 and 1, the
files from sector 2 on in the order given, each starting a sector, boot option 3 (*EXEC
!BOOT on SHIFT+BREAK).  NAME may carry a DFS directory ('D.NAME'); LOAD and EXEC are
hex, LOAD 0 and EXEC LOAD unless given.

Importable: build(out, title, files, boot), which tools/mkdisc.py and
tools/swatchdisc.py call.
"""
import sys


def build(out, title, files, boot=3):
    """Write the image to `out`.  files: [(name, data, load, exec)], placed from sector 2
    in order; title: the disc title (12 characters at most, 8 in sector 0 and 4 in
    sector 1); boot: the boot option (2 *RUN, 3 *EXEC).  At most 31 files, and they must
    fit the 800 sectors.  The catalogue lists the files by descending start sector, as
    DFS writes it."""
    sectors = 800
    cat0 = bytearray(256)
    cat1 = bytearray(256)
    cat0[0:8] = title[:8].ljust(8).encode()
    cat1[0:4] = title[8:12].ljust(4).encode()
    cat1[4] = 1                                 # the cycle number
    cat1[5] = len(files) * 8                    # the entries' bytes
    cat1[6] = ((boot & 3) << 4) | ((sectors >> 8) & 3)   # the boot option, sectors bits 9-8
    cat1[7] = sectors & 255
    img = bytearray(sectors * 256)
    entries = []
    sec = 2
    for (name, data, load, exe) in files:
        start = sec
        nsec = (len(data) + 255) // 256
        img[start * 256:start * 256 + len(data)] = data
        sec += nsec
        entries.append((name, load, exe, len(data), start))
    assert sec <= sectors, 'disc full (%d sectors)' % sec
    assert len(files) <= 31, 'a DFS catalogue holds 31 files'
    entries.sort(key=lambda e: -e[4])
    for i, (name, load, exe, length, start) in enumerate(entries):
        d = '$'
        if '.' in name:
            d, name = name.split('.', 1)
        o = 8 + i * 8
        cat0[o:o + 7] = name[:7].ljust(7).encode()
        cat0[o + 7] = ord(d)                    # the directory (its bit 7, locked, clear)
        cat1[o] = load & 255
        cat1[o + 1] = (load >> 8) & 255
        cat1[o + 2] = exe & 255
        cat1[o + 3] = (exe >> 8) & 255
        cat1[o + 4] = length & 255
        cat1[o + 5] = (length >> 8) & 255
        # bits 17-16 of exec, length and load, and bits 9-8 of the start sector
        cat1[o + 6] = (((exe >> 16) & 3) << 6) | (((length >> 16) & 3) << 4) | (((load >> 16) & 3) << 2) | ((start >> 8) & 3)
        cat1[o + 7] = start & 255
    img[0:256] = cat0
    img[256:512] = cat1
    open(out, 'wb').write(img)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    files = []
    for spec in sys.argv[3:]:
        parts = spec.split(':')
        load = int(parts[2], 16) if len(parts) > 2 else 0
        exe = int(parts[3], 16) if len(parts) > 3 else load
        files.append((parts[0], open(parts[1], 'rb').read(), load, exe))
    build(sys.argv[1], sys.argv[2], files)
