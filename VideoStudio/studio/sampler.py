"""Single-decode sampling of every screen region at once.

FFmpeg decodes the recording one time, drops to `fps` samples per second, crops each
calibrated region at native resolution (so OCR sees real pixels) plus a small overview
of the whole frame, and stacks them into one mosaic image per sample. Python reads the
mosaics from a pipe one at a time, so memory use stays constant for any video length.
"""
from __future__ import annotations

import os
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import numpy as np

from .config import ROI
from .media import FFMPEG, MediaError, MediaInfo, popen

MAX_REGION_WIDTH = 960


@dataclass(frozen=True)
class Region:
    name: str
    box: tuple[int, int, int, int]  # source pixels x, y, w, h
    out_w: int
    out_h: int
    y_off: int


@dataclass(frozen=True)
class MosaicLayout:
    regions: tuple[Region, ...]
    width: int
    height: int

    @property
    def names(self) -> list[str]:
        return [r.name for r in self.regions]

    @property
    def frame_bytes(self) -> int:
        return self.width * self.height * 3

    @classmethod
    def from_rois(cls, info: MediaInfo, rois: dict[str, ROI], overview: tuple[int, int] = (320, 180)) -> "MosaicLayout":
        specs = [("overview", (0, 0, info.width, info.height), overview[0], overview[1])]
        for name, roi in rois.items():
            x, y, w, h = roi.to_pixels(info.width, info.height)
            out_w, out_h = w, h
            if w > MAX_REGION_WIDTH:
                out_w = MAX_REGION_WIDTH
                out_h = max(2, int(round(h * MAX_REGION_WIDTH / w / 2)) * 2)
            specs.append((name, (x, y, w, h), out_w, out_h))
        regions, y_off = [], 0
        for name, box, out_w, out_h in specs:
            regions.append(Region(name, box, out_w, out_h, y_off))
            y_off += out_h
        return cls(tuple(regions), max(r.out_w for r in regions), y_off)

    def filter_graph(self, fps: float) -> str:
        n = len(self.regions)
        parts = [f"[0:v]fps={fps}:round=near,split={n}" + "".join(f"[s{i}]" for i in range(n))] if n > 1 else \
                [f"[0:v]fps={fps}:round=near[s0]"]
        for i, r in enumerate(self.regions):
            x, y, w, h = r.box
            chain = []
            if r.name != "overview":
                chain.append(f"crop={w}:{h}:{x}:{y}")
            if (r.out_w, r.out_h) != (w, h):
                chain.append(f"scale={r.out_w}:{r.out_h}:flags=area")
            if r.out_w != self.width:
                chain.append(f"pad={self.width}:{r.out_h}:0:0")
            chain.append("format=bgr24")
            parts.append(f"[s{i}]" + ",".join(chain) + f"[o{i}]")
        if n > 1:
            parts.append("".join(f"[o{i}]" for i in range(n)) + f"vstack=inputs={n}[out]")
        else:
            parts.append("[o0]null[out]")
        return ";".join(parts)

    def split(self, mosaic: np.ndarray) -> dict[str, np.ndarray]:
        return {r.name: mosaic[r.y_off:r.y_off + r.out_h, :r.out_w] for r in self.regions}


@dataclass
class Sample:
    t: float
    regions: dict[str, np.ndarray]


def sampler_command(path: Path, layout: MosaicLayout, fps: float, start: float = 0.0, duration: float | None = None,
                    threads: int | None = None, hwaccel: str | None = "auto") -> list[str]:
    cmd = [FFMPEG, "-hide_banner", "-v", "error", "-nostdin"]
    if hwaccel:
        cmd += ["-hwaccel", hwaccel]
    if threads:
        cmd += ["-threads", str(threads), "-filter_threads", str(threads)]
    if start:
        cmd += ["-ss", f"{start:.3f}"]
    if duration is not None:
        cmd += ["-t", f"{duration:.3f}"]
    cmd += ["-i", str(path), "-filter_complex", layout.filter_graph(fps), "-map", "[out]", "-an",
            "-f", "rawvideo", "-pix_fmt", "bgr24", "-"]
    return cmd


def default_threads() -> int:
    return max(1, (os.cpu_count() or 2) // 2)


def iter_samples(path: Path, layout: MosaicLayout, fps: float = 2.0, start: float = 0.0, duration: float | None = None,
                 threads: int | None = None, hwaccel: str | None = "auto") -> Iterator[Sample]:
    """Yield one Sample per 1/fps seconds. Falls back to software decode if HW decode fails."""
    threads = threads or default_threads()
    yielded = 0
    with tempfile.TemporaryFile() as err:
        proc = popen(sampler_command(path, layout, fps, start, duration, threads, hwaccel),
                     stdout=-1, stderr=err, bufsize=layout.frame_bytes)
        try:
            while True:
                buf = proc.stdout.read(layout.frame_bytes)
                if len(buf) < layout.frame_bytes:
                    break
                mosaic = np.frombuffer(buf, np.uint8).reshape(layout.height, layout.width, 3)
                yield Sample(round(start + yielded / fps, 3), layout.split(mosaic))
                yielded += 1
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.stdout.close()
            code = proc.wait()
        if code not in (0, None) and yielded == 0:
            err.seek(0)
            message = err.read().decode("utf-8", "replace")[-2000:]
            if hwaccel:
                yield from iter_samples(path, layout, fps, start, duration, threads, hwaccel=None)
                return
            raise MediaError(f"Sampling failed: {message}")
