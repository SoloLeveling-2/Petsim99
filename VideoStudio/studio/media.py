"""FFmpeg/FFprobe helpers and protection for original recordings.

Every subprocess call passes a list of arguments (never a shell string) so paths with
spaces or non-ASCII characters work on Windows, macOS and Linux alike.
"""
from __future__ import annotations

import hashlib
import json
import os
import shlex
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

FFMPEG = os.environ.get("STUDIO_FFMPEG", "ffmpeg")
FFPROBE = os.environ.get("STUDIO_FFPROBE", "ffprobe")


class MediaError(RuntimeError):
    pass


class SourceModifiedError(MediaError):
    pass


class UnsafeOutputError(MediaError):
    pass


@dataclass(frozen=True)
class MediaInfo:
    path: str
    duration: float
    width: int
    height: int
    fps: float
    has_audio: bool
    vcodec: str
    size: int


def _low_priority_kwargs() -> dict:
    """Run helpers below normal priority so the machine stays responsive."""
    if sys.platform == "win32":
        return {"creationflags": getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)}
    return {"preexec_fn": lambda: os.nice(10)}


def popen(cmd: list[str], **kwargs) -> subprocess.Popen:
    return subprocess.Popen([str(c) for c in cmd], **_low_priority_kwargs(), **kwargs)


def run(cmd: list[str], log_path: Path | None = None, check: bool = True, timeout: float | None = None,
        cwd: Path | None = None) -> subprocess.CompletedProcess:
    cmd = [str(c) for c in cmd]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                          timeout=timeout, cwd=cwd, **_low_priority_kwargs())
    if log_path is not None:
        log_path = Path(log_path)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write("$ " + " ".join(shlex.quote(c) for c in cmd) + "\n")
            fh.write(f"[exit {proc.returncode}]\n")
            if proc.stderr:
                fh.write(proc.stderr[-20000:] + "\n")
    if check and proc.returncode != 0:
        tail = "\n".join((proc.stderr or "").strip().splitlines()[-12:])
        raise MediaError(f"{Path(cmd[0]).name} failed (exit {proc.returncode}):\n{tail}")
    return proc


def _parse_rate(rate: str | None) -> float:
    if not rate or rate in ("0/0", "0"):
        return 0.0
    if "/" in rate:
        num, den = rate.split("/", 1)
        return float(num) / float(den) if float(den) else 0.0
    return float(rate)


def probe(path: Path | str) -> MediaInfo:
    path = Path(path)
    if not path.is_file():
        raise MediaError(f"Not a file: {path}")
    proc = run([FFPROBE, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path])
    data = json.loads(proc.stdout)
    video = next((s for s in data.get("streams", []) if s.get("codec_type") == "video"), None)
    if video is None:
        raise MediaError(f"No video stream in {path}")
    has_audio = any(s.get("codec_type") == "audio" for s in data.get("streams", []))
    duration = float(data.get("format", {}).get("duration") or video.get("duration") or 0.0)
    fps = _parse_rate(video.get("avg_frame_rate")) or _parse_rate(video.get("r_frame_rate"))
    return MediaInfo(
        path=str(path),
        duration=duration,
        width=int(video["width"]),
        height=int(video["height"]),
        fps=round(fps, 3),
        has_audio=has_audio,
        vcodec=video.get("codec_name", ""),
        size=path.stat().st_size,
    )


def sha256_file(path: Path | str, chunk: int = 8 << 20) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        while block := fh.read(chunk):
            digest.update(block)
    return digest.hexdigest()


@dataclass(frozen=True)
class Fingerprint:
    path: str
    size: int
    mtime_ns: int
    sha256: str


class SourceGuard:
    """Records a recording's fingerprint and proves it was never modified.

    The pipeline only ever passes the source to FFmpeg/FFprobe as an input. This guard
    additionally refuses to let any output land on the source or next to it, and checks
    size/mtime (quick) or the full SHA-256 (thorough) after each command.
    """

    def __init__(self, path: Path | str, fingerprint: dict | None = None):
        self.path = Path(path).resolve()
        if not self.path.is_file():
            raise MediaError(f"Source recording not found: {self.path}")
        if fingerprint is not None:
            self.fingerprint = Fingerprint(**fingerprint)
            self.verify()
        else:
            stat = self.path.stat()
            self.fingerprint = Fingerprint(str(self.path), stat.st_size, stat.st_mtime_ns, sha256_file(self.path))

    def as_dict(self) -> dict:
        return asdict(self.fingerprint)

    def verify(self, full: bool = False) -> None:
        stat = self.path.stat()
        if stat.st_size != self.fingerprint.size or stat.st_mtime_ns != self.fingerprint.mtime_ns:
            raise SourceModifiedError(f"Source recording changed on disk: {self.path}")
        if full and sha256_file(self.path) != self.fingerprint.sha256:
            raise SourceModifiedError(f"Source recording content changed: {self.path}")

    def check_output(self, out_path: Path | str) -> Path:
        out = Path(out_path).resolve()
        if out == self.path or out.parent == self.path.parent:
            raise UnsafeOutputError(f"Refusing to write next to the original recording: {out}")
        return out
