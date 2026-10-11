"""Shared helpers for the v5.2 offline tests.

The module tests run the real module source (sliced from the built bundle)
on Lua 5.4 against the mock engine in mock_engine.lua. They prove module
logic and safety gates against fake game data; they do NOT prove the live
PS99 server accepts any request.
"""
from pathlib import Path
import ctypes
import re

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = ROOT / "dist" / "RankPilot_X_v5_2.lua"
MOCK = Path(__file__).resolve().parent / "mock_engine.lua"

_lib = ctypes.CDLL("liblua5.4.so.0")
_lib.luaL_newstate.restype = ctypes.c_void_p
_lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
_lib.luaL_loadbufferx.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_char_p]
_lib.luaL_loadbufferx.restype = ctypes.c_int
_lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
_lib.lua_pcallk.restype = ctypes.c_int
_lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
_lib.lua_tolstring.restype = ctypes.c_char_p
_lib.lua_close.argtypes = [ctypes.c_void_p]


def bundle_text() -> str:
    return BUNDLE.read_text()


def lua54(source: str) -> str:
    """Strip the only Luau-only syntax the shipped file uses (local type annotations)."""
    source = re.sub(r"(local\s+\w+):\s*(?:any|number\??)", r"\1", source)
    return source


def module_region(source: str | None = None) -> str:
    """The spliced v5.2 module code: from the module banner to the UI banner."""
    source = source or bundle_text()
    start = source.index("-- @@RANKPILOT_MODULES@@") if "-- @@RANKPILOT_MODULES@@" in source else source.index("-- ==== module: ")
    stop = source.index("-- RANKPILOT v2.8 UI", start)
    stop = source.rindex("-- ====", start, stop)
    return source[start:stop]


def module_source(name: str, source: str | None = None) -> str:
    """One module's code (by file name, e.g. '20_rewards.lua')."""
    region = module_region(source)
    head = "-- ==== module: " + name + " ===="
    start = region.index(head)
    nxt = region.find("-- ==== module: ", start + len(head))
    return region[start:nxt if nxt >= 0 else len(region)]


def run(code: str, name: str = "test") -> None:
    """Load and run Lua 5.4 code; raise AssertionError with the Lua message on failure."""
    state = _lib.luaL_newstate()
    _lib.luaL_openlibs(state)
    try:
        data = code.encode()
        rc = _lib.luaL_loadbufferx(state, data, len(data), ("=" + name).encode(), None)
        if rc != 0:
            raise AssertionError("load: " + (_lib.lua_tolstring(state, -1, None) or b"").decode())
        rc = _lib.lua_pcallk(state, 0, 0, 0, 0, None)
        if rc != 0:
            raise AssertionError("run: " + (_lib.lua_tolstring(state, -1, None) or b"").decode())
    finally:
        _lib.lua_close(state)


def run_modules(test_lua: str, names: list[str] | None = None, setup: str = "", name: str = "modules") -> None:
    """Mock engine + selected modules (framework always first) + test body."""
    source = bundle_text()
    if names is None:
        body = module_region(source)
    else:
        wanted = ["00_framework.lua"] + [n for n in names if n != "00_framework.lua"]
        body = "\n".join(module_source(n, source) for n in wanted)
    code = MOCK.read_text() + "\n" + setup + "\n" + lua54(body) + "\n" + test_lua
    run(code, name)
