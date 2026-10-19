"""The sideways RAM build's machine for the tests: banks 4..7 behind ROMSEL.

SWR=1 in the environment selects the build (buildswr/, else build32/).  attach()
gives a py65 ObservableMemory the four banks (B4 .. B7, each file padded to 16K): a
write to ROMSEL ($FE30) pages one in at $8000, and the bank paged out keeps what was
written to it.  load() puts LAND at $3000 and the loader, LANDER, at $7000.
"""
import os

SWR = os.environ.get('SWR') == '1'
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
B = os.path.join(ROOT, os.environ.get('BDIR', 'buildswr') if SWR else 'build32')
ROMSEL = 0xFE30


def attach(mem):
    """Banks 4..7 behind ROMSEL on mem; returns them ({n: bytearray}) and the one paged
    in ([n])."""
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
    return banks, cur


def load(mem):
    """LAND at $3000, LANDER at $7000."""
    for name, at in (('LAND', 0x3000), ('LANDER', 0x7000)):
        data = open(os.path.join(B, name), 'rb').read()
        mem._subject[at:at + len(data)] = data
