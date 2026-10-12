"""Background music: an original generated track plus a license manifest for any other.

Nothing here downloads music. The default track is synthesised from code in this file,
so it is an original work with no third-party samples, melodies or rights holders.
Any track you add must carry license metadata or the renderer refuses to use it.
"""
from __future__ import annotations

import json
import wave
from pathlib import Path

import numpy as np

from .config import STUDIO_ROOT

LIBRARY = STUDIO_ROOT / "music" / "library.json"
LICENSE_TYPES = {"owned", "royalty_free", "licensed", "platform_library"}
SR = 48000

# A minor: Am - F - C - G (root, chord tones as MIDI note numbers)
_PROGRESSION = [(45, (57, 60, 64)), (41, (57, 60, 65)), (48, (55, 60, 64)), (43, (55, 59, 62))]
_PENTATONIC = [69, 72, 74, 76, 79, 81]


def _hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def _env(n: int, attack: float, decay: float) -> np.ndarray:
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / max(decay, 1e-4))


def _saw(freq: float, n: int, harmonics: int, phase: float = 0.0) -> np.ndarray:
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, harmonics + 1):
        if freq * k > SR / 2.2:
            break
        out += np.sin(2 * np.pi * freq * k * t + phase * k) / k
    return out


def _add(buf: np.ndarray, start: float, sig: np.ndarray, pan: float = 0.0, gain: float = 1.0) -> None:
    i = int(start * SR)
    if i >= buf.shape[0]:
        return
    sig = sig[: buf.shape[0] - i] * gain
    buf[i:i + sig.size, 0] += sig * np.sqrt(0.5 * (1 - pan))
    buf[i:i + sig.size, 1] += sig * np.sqrt(0.5 * (1 + pan))


def render_music(seconds: float, bpm: float = 124, seed: int = 7) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(round(seconds * SR))
    mix = np.zeros((n, 2))
    beat = 60.0 / bpm
    bars = int(np.ceil(seconds / (4 * beat)))
    arp_pattern = rng.permutation([0, 1, 2, 1, 2, 0, 2, 1])
    melody = rng.choice(_PENTATONIC, size=16)
    kick_env = np.zeros(n)

    kick_len = int(0.35 * SR)
    tk = np.arange(kick_len) / SR
    kick = np.sin(2 * np.pi * np.cumsum(45 + 90 * np.exp(-tk * 28)) / SR) * np.exp(-tk * 9)
    clap_len = int(0.18 * SR)
    hat_len = int(0.05 * SR)

    for bar in range(bars):
        t_bar = bar * 4 * beat
        root, chord = _PROGRESSION[bar % 4]
        intro = bar < 2
        lift = bar % 8 == 7
        # pad: three detuned saws per chord tone, soft and wide
        pad_n = int(4 * beat * SR)
        pad = sum(_saw(_hz(m) * d, pad_n, 6, phase=rng.uniform(0, 6)) for m in chord for d in (0.997, 1.0, 1.003))
        pad *= np.minimum(1, np.arange(pad_n) / (0.4 * SR)) * np.minimum(1, (pad_n - np.arange(pad_n)) / (0.3 * SR))
        _add(mix, t_bar, pad, pan=0.0, gain=0.018)
        for b in range(4):
            tb = t_bar + b * beat
            if not intro:
                _add(mix, tb, kick, gain=0.55)
                seg = kick_env[int(tb * SR):int(tb * SR) + kick_len]
                seg[:] = np.maximum(seg, np.exp(-tk[:seg.size] * 7))
                if b in (1, 3):
                    noise = rng.standard_normal(clap_len)
                    _add(mix, tb, (noise + 0.6 * np.sin(2 * np.pi * 190 * np.arange(clap_len) / SR))
                         * _env(clap_len, 0.002, 0.045), gain=0.16)
            for half in (0, 1):  # hats on eighths, open-ish on offbeats
                hat = np.diff(rng.standard_normal(hat_len + 1)) * _env(hat_len, 0.001, 0.012 if half == 0 else 0.022)
                _add(mix, tb + half * beat / 2, hat, pan=0.3, gain=0.05 if half == 0 else 0.08)
            if not intro:  # bass on eighths: root, octave
                for half in (0, 1):
                    bn = int(beat / 2 * SR * 0.9)
                    note = root + (12 if half else 0) - 12
                    _add(mix, tb + half * beat / 2, _saw(_hz(note), bn, 8) * _env(bn, 0.004, 0.18), gain=0.16)
            for s in range(4):  # plucked arpeggio on sixteenths, ping-pong
                step = (b * 4 + s) % 8
                pn = int(beat / 4 * SR * 1.6)
                note = chord[arp_pattern[step] % 3] + 12
                sig = np.sign(np.sin(2 * np.pi * _hz(note) * np.arange(pn) / SR)) * _env(pn, 0.002, 0.07)
                _add(mix, tb + s * beat / 4, sig, pan=-0.5 if s % 2 else 0.5, gain=0.035 if not intro else 0.02)
        if lift:  # snare roll into the next phrase
            for k in range(8):
                roll = rng.standard_normal(clap_len // 2) * _env(clap_len // 2, 0.001, 0.03)
                _add(mix, t_bar + 3 * beat + k * beat / 8, roll, gain=0.05 + 0.012 * k)
        if bar % 16 >= 8:  # hook melody in alternate phrases
            for q in range(8):
                ln = int(beat / 2 * SR * 0.95)
                note = melody[(bar % 2) * 8 + q]
                lead = (_saw(_hz(note), ln, 5) + 0.5 * np.sin(2 * np.pi * _hz(note + 12) * np.arange(ln) / SR))
                _add(mix, t_bar + q * beat / 2, lead * _env(ln, 0.01, 0.25), pan=0.1, gain=0.045)

    duck = 1 - 0.45 * kick_env  # sidechain pump on everything but the kick itself
    mix *= duck[:, None]
    mix = np.tanh(mix * 1.6)
    fade = int(0.02 * SR)
    mix[:fade] *= np.linspace(0, 1, fade)[:, None]
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return mix * (10 ** (-1.5 / 20) / max(1e-9, np.abs(mix).max()))


def write_wav(path: Path, audio: np.ndarray) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(np.round(audio * 32767), -32768, 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(audio.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return path


def generate_track(path: Path, seconds: float = 90.0, bpm: float = 124, seed: int = 7) -> Path:
    return write_wav(path, render_music(seconds, bpm, seed))


def load_library(path: Path = LIBRARY) -> list[dict]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    base = Path(path).parent
    tracks = []
    for track in data["tracks"]:
        track = dict(track)
        if track.get("file") and not Path(track["file"]).is_absolute():
            track["file"] = str(base / track["file"])
        tracks.append(track)
    return tracks


def validate_track(track: dict, require_file: bool = True) -> list[str]:
    errors = []
    for field in ("id", "title", "file"):
        if not track.get(field):
            errors.append(f"missing {field}")
    if not str(track.get("license", "")).strip():
        errors.append("missing license text")
    if track.get("license_type") not in LICENSE_TYPES:
        errors.append(f"license_type must be one of {sorted(LICENSE_TYPES)}")
    if not str(track.get("proof", "")).strip():
        errors.append("missing proof of license (invoice, library URL, or generator)")
    if not track.get("allowed_platforms"):
        errors.append("missing allowed_platforms")
    if require_file and track.get("file") and not Path(track["file"]).is_file() and not track.get("generator"):
        errors.append(f"file not found: {track['file']}")
    return errors


def pick_track(library: list[dict], platforms: list[str], prefer: str | None = None) -> dict:
    usable = [t for t in library if not validate_track(t) and set(platforms) <= set(t["allowed_platforms"])]
    usable.sort(key=lambda t: t["id"] != prefer)
    if not usable:
        raise ValueError(f"No licensed track allowed on all of {platforms}. Add one with license metadata "
                         f"to {LIBRARY.name}.")
    return usable[0]


def ensure_track_file(track: dict) -> Path:
    path = Path(track["file"])
    if not path.is_file():
        gen = track.get("generator")
        if not gen:
            raise FileNotFoundError(path)
        generate_track(path, **gen)
    return path
