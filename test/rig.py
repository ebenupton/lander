"""The build under test and its machine, for the tests and the tools that read a build.

The build is named by the environment, as test/gate.sh and build.sh name it:

    SWR=1     the sideways RAM build (otherwise the 32K build)
    VERSION   mode1, cpc, nula or arc; unset, the version that ARC=1, NULA=1 or CPC=1
              names, mode1 without any
    BUILD     build.sh's output directory (default build; a relative one is taken
              from the repository's root, as build.sh takes it)
    BDIR      the build's own directory, in place of BUILD/<base|swr>-VERSION

Importing this module sets CPC, NULA and ARC from VERSION, which proto/nula.py reads:
import it before proto's modules.

    SWR, VERSION   the build
    BUILD          build.sh's output directory
    B              the build's directory
    labels(name)   a label file of the build's: {name: address}
    attach(mem)    banks 4 to 7 behind ROMSEL on a py65 ObservableMemory
    started(...)   the machine as the program's start leaves it
"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
VERSIONS = ('mode1', 'cpc', 'nula', 'arc')
ROMSEL = 0xFE30


def _version():
    v = os.environ.get('VERSION')
    if not v:
        on = lambda k: os.environ.get(k, '0') not in ('', '0')
        return 'arc' if on('ARC') else 'nula' if on('NULA') else 'cpc' if on('CPC') else 'mode1'
    if v not in VERSIONS:
        raise SystemExit(f'VERSION={v}: not one of {", ".join(VERSIONS)}')
    for k in ('CPC', 'NULA', 'ARC'):
        os.environ[k] = '1' if k.lower() == v else '0'
    return v


SWR = os.environ.get('SWR') == '1'
VERSION = _version()
BUILD = os.path.join(ROOT, os.environ.get('BUILD') or 'build')
B = os.environ.get('BDIR') or os.path.join(BUILD, ('swr-' if SWR else 'base-') + VERSION)


def labels(name='labels.txt'):
    """ld65's label file B/name (lines "al <hex> .<name>"): {name: address}."""
    out = {}
    for ln in open(os.path.join(B, name)):
        _, a, n = ln.split()
        out[n.lstrip('.')] = int(a, 16)
    return out


def attach(mem):
    """Banks 4 to 7 (B4 .. B7, each padded to 16K) behind ROMSEL on mem: a write to
    ROMSEL ($FE30) pages one in at $8000, and the bank paged out keeps what was written
    to it."""
    banks = {n: bytearray(open(os.path.join(B, f'B{n}'), 'rb').read().ljust(0x4000, b'\0'))
             for n in (4, 5, 6, 7)}
    cur = [None]

    def romsel(addr, value):
        n = value & 15
        if n in banks and n != cur[0]:
            if cur[0] is not None:
                banks[cur[0]][:] = bytes(mem._subject[0x8000:0xC000])
            mem._subject[0x8000:0xC000] = banks[n]
            cur[0] = n
        return value
    mem.subscribe_to_write([ROMSEL], romsel)


def load(mem):
    """The program's file where the loader loads it: MAIN at $3000 (the sideways RAM
    build), BASE at $2000."""
    name, at = ('MAIN', 0x3000) if SWR else ('BASE', 0x2000)
    data = open(os.path.join(B, name), 'rb').read()
    mem._subject[at:at + len(data)] = data


def started(mem, lab, call):
    """The machine after the program's start: the banks attached (the sideways RAM
    build), the file loaded, takeover run through call(address), and the start-up
    code's pages cleared as its last stub clears them."""
    if SWR:
        attach(mem)
    load(mem)
    call(lab['takeover'])
    at = lab['__BOOT_LOAD__'] & 0xFF00
    mem._subject[at:lab['LAND1']] = bytes(lab['LAND1'] - at)
