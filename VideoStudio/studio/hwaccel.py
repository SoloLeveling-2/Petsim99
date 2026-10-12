"""Pick the best working H.264 encoder by actually opening each one.

An encoder being compiled into FFmpeg says nothing about whether this machine has the
GPU and driver for it, so each candidate is tested with a tiny real encode.
"""
from __future__ import annotations

from dataclasses import dataclass

from .media import FFMPEG, run, MediaError

ENCODER_PRIORITY = ("h264_nvenc", "h264_qsv", "h264_amf", "h264_videotoolbox", "h264_vaapi", "libx264")

VAAPI_DEVICE = "/dev/dri/renderD128"

# Quality-oriented settings for 1080x1920 30 fps short-form output (~10-16 Mbps).
_ARGS = {
    "h264_nvenc": ["-preset", "p5", "-tune", "hq", "-rc", "vbr", "-cq", "21", "-b:v", "0",
                   "-maxrate", "20M", "-bufsize", "40M", "-profile:v", "high"],
    "h264_qsv": ["-preset", "medium", "-global_quality", "22", "-profile:v", "high"],
    "h264_amf": ["-quality", "quality", "-rc", "cqp", "-qp_i", "20", "-qp_p", "22", "-qp_b", "24",
                 "-profile:v", "high"],
    "h264_videotoolbox": ["-b:v", "14M", "-maxrate", "20M", "-profile:v", "high"],
    "h264_vaapi": ["-qp", "22", "-profile:v", "high"],
    "libx264": ["-preset", "medium", "-crf", "20", "-profile:v", "high"],
}


@dataclass(frozen=True)
class EncoderChoice:
    name: str
    args: tuple[str, ...]
    pre_filter: str
    global_args: tuple[str, ...]
    hw: bool


def _choice(name: str) -> EncoderChoice:
    if name == "h264_vaapi":
        return EncoderChoice(name, tuple(_ARGS[name]), "format=nv12,hwupload", ("-vaapi_device", VAAPI_DEVICE), True)
    return EncoderChoice(name, tuple(_ARGS[name]), "format=yuv420p", (), name != "libx264")


def probe_encoders(ffmpeg: str = FFMPEG, timeout: float = 30) -> dict[str, bool]:
    available: dict[str, bool] = {}
    for name in ENCODER_PRIORITY:
        choice = _choice(name)
        cmd = [ffmpeg, "-hide_banner", "-v", "error", *choice.global_args,
               "-f", "lavfi", "-i", "color=c=black:s=256x256:r=30:d=0.2",
               "-vf", choice.pre_filter, "-frames:v", "5", "-c:v", name, "-f", "null", "-"]
        try:
            available[name] = run(cmd, check=False, timeout=timeout).returncode == 0
        except (OSError, MediaError, TimeoutError):
            available[name] = False
        except Exception:  # subprocess.TimeoutExpired and friends
            available[name] = False
    return available


def choose_encoder(available: dict[str, bool], prefer: str | None = None) -> EncoderChoice:
    if prefer and available.get(prefer):
        return _choice(prefer)
    for name in ENCODER_PRIORITY:
        if available.get(name):
            return _choice(name)
    raise MediaError("No working H.264 encoder found (not even libx264). Install a full FFmpeg build.")
