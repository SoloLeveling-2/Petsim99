"""Brand template and per-source calibration profiles."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

STUDIO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROFILE = STUDIO_ROOT / "profiles" / "ps99_default.json"
DEFAULT_BRAND = STUDIO_ROOT / "brand" / "brand.json"
WORKSPACE = Path(os.environ.get("STUDIO_WORKSPACE", STUDIO_ROOT / "workspace"))

ROI_NAMES = ("star_counter", "quest_panel", "completion_banner", "rank_label")


@dataclass(frozen=True)
class ROI:
    """A screen region in normalized coordinates (0-1) of the source frame."""
    x: float
    y: float
    w: float
    h: float

    def to_pixels(self, width: int, height: int) -> tuple[int, int, int, int]:
        x = max(0, min(width - 2, int(round(self.x * width))))
        y = max(0, min(height - 2, int(round(self.y * height))))
        w = max(2, min(width - x, int(round(self.w * width))))
        h = max(2, min(height - y, int(round(self.h * height))))
        return x - x % 2, y - y % 2, w - w % 2, h - h % 2


@dataclass
class Profile:
    name: str
    rois: dict[str, ROI] = field(default_factory=dict)
    suggested_rois: dict[str, ROI] = field(default_factory=dict)
    star_pattern: str = r"(?P<cur>\d{1,5})\s*/\s*(?P<total>\d{1,5})"
    sample_fps: float = 2.0
    max_gain: int = 60
    confirm_samples: int = 3
    revert_window: float = 5.0
    ocr_min_conf: float = 0.6
    banner_keywords: list[str] = field(default_factory=lambda: ["complete", "rank up", "quest"])
    notes: str = ""

    @property
    def calibrated(self) -> bool:
        return "star_counter" in self.rois


def _rois(data: dict) -> dict[str, ROI]:
    return {name: ROI(**vals) for name, vals in (data or {}).items()}


def load_profile(path: Path | str) -> Profile:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    data["rois"] = _rois(data.get("rois"))
    data["suggested_rois"] = _rois(data.get("suggested_rois"))
    return Profile(**data)


def profile_to_dict(profile: Profile) -> dict:
    out = dict(profile.__dict__)
    out["rois"] = {k: vars(v) for k, v in profile.rois.items()}
    out["suggested_rois"] = {k: vars(v) for k, v in profile.suggested_rois.items()}
    return out


def save_profile(profile: Profile, path: Path | str) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(profile_to_dict(profile), indent=2), encoding="utf-8")


def load_brand(path: Path | str | None = None) -> dict:
    return json.loads(Path(path or DEFAULT_BRAND).read_text(encoding="utf-8"))
