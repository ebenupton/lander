#!/usr/bin/env python3
"""The disc, lander.ssd: one 80-track DFS image for every machine and version.

    python3 tools/mkdisc.py BUILD OUT.ssd

BUILD holds the loader (BUILD/loader/BOOT, its labels beside it) and the eight builds,
BUILD/base-V and BUILD/swr-V for V in mode1, cpc, nula, arc (build.sh).  The files:

    $.!BOOT             the loader (src/loader.s), *RUN by SHIFT+BREAK (boot option 2)
    d.BASE              the 32K build of version d, loaded at $2000
    $.BANK4 $.BANK6     the sideways RAM build's bank images that the versions share:
    $.BANK7             the MODE 1 build's, each 16K less its trailing zeros
    d.BANK5             version d's bank 5 (the tiles' colours, the game)
    d.MAIN              version d's main RAM part, loaded at $3000, ending with its
                        patch records

d is the version's directory: M (mode1), C (cpc), N (nula), A (arc).  A version's banks
4, 6 and 7 differ from the shared images in a few hundred bytes (colours, and the arc
build's setup); those differences are its patch records, which its start writes into the
banks (src/boot.s, patch): a bank (4 .. 7), an address, a length (1 .. 255) and the
bytes, the list ended by a zero.  Every load address has the high bits that keep the
file in the I/O processor when a second processor is on.

Checks: each version's images rebuilt from the shared ones and its records, byte for
byte; MAIN within screen 0; BASE below the loader; the catalogue's 31 files and the
disc's 800 sectors (tools/mkdfs.py).  Prints the catalogue and the sectors free.
tools/memmap.py imports catalogue().
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkdfs  # noqa: E402

VERSIONS = (('mode1', 'M'), ('cpc', 'C'), ('nula', 'N'), ('arc', 'A'))
SHARED = (4, 6, 7)                 # the banks stored once
HOST = 0x30000                     # a load address's bits 17-16: the I/O processor
BASE, STAGE, LOADER = 0x2000, 0x3000, 0x7000
SCREEN1 = 0x5800                   # the sideways RAM build's second screen
GAP = 4                            # differences this close share a record


def labels(path):
    """ld65's label file: {name: address}."""
    out = {}
    for ln in open(path):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


def bank(build, v, n):
    """Version v's bank n, 16K."""
    return open(os.path.join(build, f'swr-{v}', f'B{n}'), 'rb').read().ljust(0x4000, b'\0')


def records(ref, img, n):
    """The patch records turning bank n's image ref into img."""
    diff = [i for i in range(0x4000) if ref[i] != img[i]]
    runs = []
    for i in diff:
        if runs and i - runs[-1][1] <= GAP:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    out = bytearray()
    for lo, hi in runs:
        while lo <= hi:
            ln = min(255, hi - lo + 1)
            out += bytes([n, lo & 255, 0x80 + (lo >> 8), ln]) + img[lo:lo + ln]
            lo += ln
    return bytes(out)


def apply(images, recs):
    """The shared images ({bank: bytes}) with the records written in, as patch does."""
    out = {n: bytearray(v) for n, v in images.items()}
    i = 0
    while recs[i]:
        n, a, ln = recs[i], recs[i + 1] | recs[i + 2] << 8, recs[i + 3]
        out[n][a - 0x8000:a - 0x8000 + ln] = recs[i + 4:i + 4 + ln]
        i += 4 + ln
    return out


def catalogue(build):
    """The disc's files, [(name, data, load, exec)], and the bytes of patch records."""
    lab = labels(os.path.join(build, 'loader', 'labels.txt'))
    files = [('!BOOT', open(os.path.join(build, 'loader', 'BOOT'), 'rb').read(),
              HOST | LOADER, HOST | lab['start'])]
    shared = {n: bank(build, 'mode1', n) for n in SHARED}
    for n in SHARED:
        files.append((f'BANK{n}', shared[n].rstrip(b'\0'), HOST | STAGE, HOST | STAGE))
    patched = 0
    for v, d in VERSIONS:
        lab = labels(os.path.join(build, f'base-{v}', 'labels.txt'))
        data = open(os.path.join(build, f'base-{v}', 'BASE'), 'rb').read()
        assert BASE + len(data) <= LOADER, f'{v}: BASE below the loader'
        files.append((f'{d}.BASE', data, HOST | BASE, HOST | lab['start']))
        lab = labels(os.path.join(build, f'swr-{v}', 'labels.txt'))
        main_ = open(os.path.join(build, f'swr-{v}', 'MAIN'), 'rb').read()
        assert lab['patches'] == STAGE + len(main_) - 1 and main_[-1] == 0, f'{v}: MAIN ends with patch\'s end mark'
        recs = b''.join(records(shared[n], bank(build, v, n), n) for n in SHARED) + b'\0'
        rebuilt = apply(shared, recs)
        assert all(rebuilt[n] == bank(build, v, n) for n in SHARED), f'{v}: the patched banks'
        main_ = main_[:-1] + recs
        assert STAGE + len(main_) <= SCREEN1, f'{v}: MAIN within screen 0'
        patched += len(recs) - 1
        files.append((f'{d}.MAIN', main_, HOST | STAGE, HOST | lab['start']))
        files.append((f'{d}.BANK5', bank(build, v, 5).rstrip(b'\0'), HOST | STAGE, HOST | STAGE))
    return files, patched


def main():
    build, out = sys.argv[1], sys.argv[2]
    files, patched = catalogue(build)
    mkdfs.build(out, 'LANDER', files, boot=2)
    used = 2
    print(f'{"file":10s} {"load":>6s} {"exec":>6s} {"bytes":>6s} {"sectors":>7s}')
    for name, data, load, exe in files:
        n = (len(data) + 255) // 256
        used += n
        print(f'{name if "." in name else "$." + name:10s} {load & 0xFFFF:6X} {exe & 0xFFFF:6X} {len(data):6d} {n:7d}')
    print(f'{len(files)} files, {used} of 800 sectors, {800 - used} free; {patched} bytes of patch records')


if __name__ == '__main__':
    main()
