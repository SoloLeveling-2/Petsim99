"""Build VY_AutoRank v1.1.9 from v1.1.8 by exact single-match edits.

Usage: python3 -I patch_v119.py <v1.1.8 CRLF source> <v1.1.9 CRLF output>
Each edit must match exactly once; any mismatch aborts without writing.
v1.1.8 itself is rebuilt from the frozen v1.1.7 by patch_v118.py.
"""
import sys

src_path, out_path = sys.argv[1], sys.argv[2]
raw = open(src_path, "rb").read().decode("utf-8")
assert "\r\n" in raw
s = raw.replace("\r\n", "\n")
EDITS = []


def edit(name, old, new):
    EDITS.append((name, old, new))


# --- identity -----------------------------------------------------------------------
edit("version", 'local VERSION = "1.1.8"', 'local VERSION = "1.1.9"')
edit("header version",
"""--  VY AutoRank v1.1.7
--  Pet Simulator 99 rank automation""",
"""--  VY AutoRank v1.1.9
--  Pet Simulator 99 rank automation""")
edit("header identity note",
"""--  Every game-module call goes through gcall() (thread identity 2); GUI / VirtualUser
--  stay at identity 8. Every loop iteration is pcall-wrapped and restarts on error.""",
"""--  Every game-module call goes through gcall() (thread identity 2), which then returns
--  the thread to the identity it had (the executor's own, normally 8) for GUI /
--  VirtualUser work. Every loop iteration is pcall-wrapped and restarts on error.""")

# --- G1: gcall restores the identity it found -----------------------------------------
edit("G1 gcall restores prior identity",
"""local canSetIdentity = type(setthreadidentity) == "function"

-- Runs fn(...) at identity 2 (game modules) and restores identity 8 (executor / CoreGui).
-- Returns pcall-style results: ok, ...""",
"""local canSetIdentity = type(setthreadidentity) == "function"
local canGetIdentity = type(getthreadidentity) == "function"

-- Runs fn(...) at identity 2 (game modules), then restores the identity the thread had.
-- v1.1.9: that was always 8; a gcall inside another gcall then left the outer one at 8,
-- and an executor whose threads run below 8 was raised to 8. 8 stays the fallback.
-- Returns pcall-style results: ok, ...""")
edit("G1 gcall body",
"""    if canSetIdentity then pcall(setthreadidentity, IDENTITY_GAME) end
    local r = table.pack(pcall(fn, ...))
    if canSetIdentity then pcall(setthreadidentity, IDENTITY_EXEC) end
    return table.unpack(r, 1, r.n)""",
"""    local prior = IDENTITY_EXEC
    if canSetIdentity and canGetIdentity then
        local okId, id = pcall(getthreadidentity)
        if okId and type(id) == "number" then prior = id end
    end
    if canSetIdentity then pcall(setthreadidentity, IDENTITY_GAME) end
    local r = table.pack(pcall(fn, ...))
    if canSetIdentity then pcall(setthreadidentity, prior) end
    return table.unpack(r, 1, r.n)""")

for name, old, new in EDITS:
    count = s.count(old)
    if count != 1:
        sys.exit(f"edit '{name}': expected 1 match, found {count}")
    s = s.replace(old, new)
open(out_path, "wb").write(s.replace("\n", "\r\n").encode("utf-8"))
print(f"applied {len(EDITS)} edits -> {out_path}")
