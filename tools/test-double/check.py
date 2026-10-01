"""Exercise the installed test-double dylib like a host (issue #274).

Proves the SHIPPED artifact (not just the Zig unit tests): the
dylib loads, every scripted entry resolves, and the four scripts
answer. Metrics pass with all-NULL hooks — the double never calls
them.
"""
import ctypes
import glob
import sys

libs = sorted(glob.glob("zig-out/test-double/libzatex_test.*"))
libs = [p for p in libs if not p.endswith(".a")]
assert len(libs) == 1, libs
lib = ctypes.CDLL(libs[0])


class Run(ctypes.Structure):
    _fields_ = [("font_id", ctypes.c_uint16),
                ("size_units", ctypes.c_uint16),
                ("x", ctypes.c_int32),
                ("baseline_y", ctypes.c_int32),
                ("glyph_start", ctypes.c_uint32),
                ("glyph_count", ctypes.c_uint32),
                ("x_scale", ctypes.c_uint16),
                ("color", ctypes.c_uint32)]


class Rule(ctypes.Structure):
    _fields_ = [("x", ctypes.c_int32),
                ("y", ctypes.c_int32),
                ("w", ctypes.c_uint32),
                ("h", ctypes.c_uint32)]


class Layout(ctypes.Structure):
    _fields_ = [("width", ctypes.c_uint32),
                ("height_above", ctypes.c_uint32),
                ("depth_below", ctypes.c_uint32),
                ("nruns", ctypes.c_uint32),
                ("nrules", ctypes.c_uint32),
                ("status", ctypes.c_int32),
                ("err_offset", ctypes.c_uint32),
                ("err_msg", ctypes.c_char_p),
                ("err_msg_len", ctypes.c_size_t)]


class Metrics(ctypes.Structure):
    _fields_ = [("ctx", ctypes.c_void_p)] + [("hook%d" % i, ctypes.c_void_p)
                                             for i in range(8)]


assert ctypes.sizeof(Run) == 28, ctypes.sizeof(Run)
assert ctypes.sizeof(Layout) == 48, ctypes.sizeof(Layout)

lib.zatex_capabilities.restype = ctypes.c_uint32
lib.zatex_capabilities.argtypes = []
assert lib.zatex_capabilities() == 7, "caps"
lib.zatex_version.restype = ctypes.c_uint32
lib.zatex_version.argtypes = []
assert lib.zatex_version() == 0, "version"

lib.zatex_layout_utf8_ex.restype = ctypes.c_int32
lib.zatex_layout_utf8_ex.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                     ctypes.c_bool,
                                     ctypes.POINTER(Metrics),
                                     ctypes.POINTER(Run), ctypes.c_size_t,
                                     ctypes.c_size_t,
                                     ctypes.POINTER(Rule), ctypes.c_size_t,
                                     ctypes.POINTER(ctypes.c_uint16),
                                     ctypes.c_size_t,
                                     ctypes.POINTER(Layout)]


def lay(tex):
    m = Metrics()
    runs = (Run * 8)()
    rules = (Rule * 4)()
    glyphs = (ctypes.c_uint16 * 16)()
    out = Layout()
    st = lib.zatex_layout_utf8_ex(tex, len(tex), False, m,
                                  runs, 8, ctypes.sizeof(Run),
                                  rules, 4, glyphs, 16, out)
    return st, out, runs


st, out, runs = lay(b"\\frac{a}{b}+x^2")
assert (st, out.status, out.nruns, out.nrules) == (0, 0, 3, 1), (st, out.status)
assert (out.width, out.height_above, out.depth_below) == (2100, 900, 350)
assert runs[1].x_scale == 2000 and runs[2].color == 0xFF0000FF

st, out, _ = lay(b"__ZATEX_TD_NOSPACE__")
assert (st, out.status) == (6, 6) and (out.nruns, out.nrules) == (3, 2)

st, out, _ = lay(b"__ZATEX_TD_LIMIT__")
assert (st, out.status) == (7, 7) and out.nruns > 256 and out.nrules > 64

st, out, _ = lay(b"__ZATEX_TD_BAD__")
assert (st, out.status, out.err_offset) == (2, 2, 5) and out.err_msg_len > 0

print("test-double artifact OK:", libs[0])
