"""Opt-in posting to YouTube Shorts and TikTok (Python standard library only).

Nothing here runs unless you call `python -m studio connect <platform>` once and then
`python -m studio publish <render-id> <platform>`. Publishing requires a valid
authorization from the review dashboard, re-checks that the bytes being uploaded are
the exact file you authorized, asks you to type POST (unless --yes), and records the
result in the render's review history so the same video is never posted twice.

Credentials (OAuth client files and tokens) live in `credentials/`, which is git-ignored.
"""
from __future__ import annotations

import os
from pathlib import Path

from ..config import STUDIO_ROOT

CREDENTIALS = Path(os.environ.get("STUDIO_CREDENTIALS", STUDIO_ROOT / "credentials"))
PLATFORMS = ("youtube_shorts", "tiktok")


class PublishError(RuntimeError):
    pass
