"""gamecfg -- what the dataflow tools need to know about the game being analysed.

The tools are the engine's (beebgame/tools/dataflow); each game says what is its own in a
config file, a Python module of assignments, passed as --config (or the environment's
DATAFLOW_CONFIG).  Anything it leaves out keeps the default below: a game with none of
these features (no inline-operand helpers, no object model) needs no config at all.

    GAME_DIR          the game's sources, relative to the game's root ('src')
    ISR_ROOTS         the interrupt's entry labels (the engine's, by default)
    ISR_DATA_POINTERS pointers the interrupt reads its own data through (never the game's
                      variables); names match ignoring case and underscores
    INLINE_HELPERS    {label: (roles, uses)}: subroutines whose operands follow the JSR
                      inline, so no code analysis can follow their returns; their contract.
                      roles per operand byte: 'rw16' / 'w16' / 'r16' a zero-page word read
                      and written / written / read, 'i' an immediate byte; uses: the
                      registers read on entry ('A', 'X', 'Y').  X and Y are preserved; A N Z
                      C V are clobbered
    HELPER_SCRATCH    the helpers' own zero-page words (written by every one)
    HELPER_CARRY_X0   label prefixes of helpers that return C = bit 0 of the caller's X
    SCREEN_POINTERS   zero-page pointers the game writes the screen through (stores through
                      them are taken never to hit a variable)
    VAR_SEGMENTS      the game's variable segments (patterns.py's const_var looks there)
    LOADER_DBG        the load-time program's debug file in the build directory, analysed
                      too when the object model's records are built there (None: not)
    OBJECTS           None, or the object model (ranges.py: records summarised per type):
        records       the label of the record array
        count         the label of its record count (an equate) or a number
        stride        bytes a record
        type_field    the label of the type field's offset (an equate)
        fields        the field-offset labels, for the summary's table
        types         the type values the levels use
        type_prefix   the prefix of the type equates' names (for display)
        current       the zero-page pointer to the record being processed (its type is
                      the key of the per-type values)
        type_var      the zero-page byte the loader keeps the record's type in
        loader_file   the source file of the loader's record builder (its stores through
                      `current` build the records; its other stores into them are its clear)
        bind          a regex of the loader's store that binds the record's type
        layout        'aos' (the default: records of `stride` bytes, `current` a pointer to
                      one, fields at offsets) or 'soa' (one array of `count` bytes a field,
                      `stride` the number of fields, `records` the first array, the fields'
                      labels the arrays; `current` the byte holding the current record's
                      index -- an access is that record's when its index register equals
                      that byte, as after `ldy obj`)
        game_bind     (file, regex, routine): when the game's own code builds the records
                      (no load-time program), the instruction in that routine of that file
                      that stores the record's type into `type_var` binds it
"""
import os, importlib.util


class _C:
    GAME_DIR = 'src'
    ISR_ROOTS = ('irq_handler', 'isr_body')
    ISR_DATA_POINTERS = ()
    INLINE_HELPERS = {}
    HELPER_SCRATCH = ()
    HELPER_CARRY_X0 = ()
    SCREEN_POINTERS = ()
    VAR_SEGMENTS = ('GAMEBSS', 'ZPGAME', 'GAMEHI', 'GAMELVL')
    LOADER_DBG = None
    OBJECTS = None


C = _C()


def load(path=None):
    """read a game's config file (or $DATAFLOW_CONFIG) over the defaults"""
    path = path or os.environ.get('DATAFLOW_CONFIG')
    if not path:
        return C
    spec = importlib.util.spec_from_file_location('dataflow_game_config', path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    for k in dir(_C):
        if not k.startswith('_') and hasattr(m, k):
            setattr(C, k, getattr(m, k))
    return C


def add_args(ap):
    ap.add_argument('--config', default=None, help="the game's dataflow config (gamecfg.py)")
    ap.add_argument('--root', default=os.getcwd(), help="the game's root (default: here)")
