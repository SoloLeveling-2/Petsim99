"""Find candidate gameplay recordings on the local computer."""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path

from .media import MediaError, probe

VIDEO_EXTS = {".mp4", ".mkv", ".mov", ".flv", ".webm", ".avi", ".ts", ".m4v"}
NAME_HINTS = ("vyhub", "vy hub", "auto rank", "ranking", "rank", "ps99", "pet sim", "petsim", "roblox")
SKIP_DIRS = {"node_modules", "appdata", "$recycle.bin", "windows", "program files", "program files (x86)",
             ".git", "library", "workspace"}


@dataclass
class Candidate:
    path: Path
    duration: float
    size: int
    mtime: float
    score: float
    reasons: list[str] = field(default_factory=list)


def default_roots() -> list[Path]:
    home = Path.home()
    names = ["Videos", "Videos/Captures", "Videos/Roblox", "Videos/OBS", "Movies", "Desktop", "Downloads",
             "OneDrive/Videos", "OneDrive/Desktop", "Documents"]
    roots = []
    for name in names:
        p = home / name
        if p.is_dir() and p not in roots:
            roots.append(p)
    return roots


def _name_hits(name: str) -> list[str]:
    lowered = re.sub(r"[_\-.]+", " ", name.lower())
    return [hint for hint in NAME_HINTS if hint in lowered]


def _walk(root: Path, max_depth: int):
    root_depth = len(root.parts)
    for dirpath, dirnames, filenames in os.walk(root):
        depth = len(Path(dirpath).parts) - root_depth
        dirnames[:] = [d for d in dirnames if d.lower() not in SKIP_DIRS and not d.startswith(".")]
        if depth >= max_depth:
            dirnames[:] = []
        for filename in filenames:
            if Path(filename).suffix.lower() in VIDEO_EXTS:
                yield Path(dirpath) / filename


def find_recordings(roots: list[Path], min_s: float = 480, max_s: float = 900, max_depth: int = 4,
                    limit: int = 50) -> list[Candidate]:
    found: list[Candidate] = []
    seen: set[Path] = set()
    for root in roots:
        root = Path(root)
        if not root.is_dir():
            continue
        for path in _walk(root, max_depth):
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            try:
                info = probe(path)
            except (MediaError, OSError, ValueError):
                continue
            if not (min_s <= info.duration <= max_s):
                continue
            stat = path.stat()
            hits = _name_hits(path.name)
            reasons = [f"duration {info.duration:.0f}s within {min_s:.0f}-{max_s:.0f}s"]
            if hits:
                reasons.append("name matches: " + ", ".join(hits))
            found.append(Candidate(path, info.duration, info.size, stat.st_mtime, 10.0 * len(hits), reasons))
    found.sort(key=lambda c: (c.score, c.mtime), reverse=True)
    return found[:limit]
