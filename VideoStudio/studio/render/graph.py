"""Build the single FFmpeg command that cuts, lays out, crossfades, overlays, mixes and encodes."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from ..hwaccel import EncoderChoice
from ..media import FFMPEG

W, H = 1080, 1920


@dataclass(frozen=True)
class OverlayInput:
    kind: str                      # "png_sequence" | "ass" | "none"
    path: str                      # image pattern (e.g. overlay/frame-%04d.png) or .ass file, relative to cwd
    start_number: int = 0
    fonts_dir: str = "fonts"


def _even(v: float) -> int:
    return max(2, int(round(v / 2)) * 2)


def _crop_px(roi: dict, src_w: int, src_h: int) -> tuple[int, int, int, int]:
    x, y = int(roi["x"] * src_w) // 2 * 2, int(roi["y"] * src_h) // 2 * 2
    w = min(src_w - x, _even(roi["w"] * src_w))
    h = min(src_h - y, _even(roi["h"] * src_h))
    return x, y, w, h


def _layout_chain(i: int, plan: dict) -> list[str]:
    """Filters turning segment i's frames ([s{i}]) into a 1080x1920 frame ([v{i}])."""
    layout = plan["layout"]
    src_w, src_h = plan["source"]["width"], plan["source"]["height"]
    main = layout["main_rect"]
    panel, star = layout.get("panel_rect"), layout.get("star_rect")
    branches = 2 + (1 if panel else 0) + (1 if star else 0)
    out = [f"[s{i}]split={branches}" + "".join(f"[s{i}_{k}]" for k in range(branches))]
    # blurred, darkened backdrop: blur at quarter resolution (cheap), then upscale
    out.append(f"[s{i}_0]scale=270:480:force_original_aspect_ratio=increase,crop=270:480,boxblur=10:2,"
               f"scale={W}:{H},eq=brightness=-0.12:saturation=1.2[bg{i}]")
    scale = max(main["w"] / src_w, main["h"] / src_h)
    sw, sh = _even(src_w * scale), _even(src_h * scale)
    out.append(f"[s{i}_1]scale={sw}:{sh},crop={main['w']}:{main['h']}:{(sw - main['w']) // 2}:{(sh - main['h']) // 2}"
               f"[main{i}]")
    out.append(f"[bg{i}][main{i}]overlay={main['x']}:{main['y']}[l{i}_0]")
    last, k = f"l{i}_0", 2
    for name, rect, roi in (("panel", panel, layout.get("panel_roi")), ("star", star, layout.get("star_roi"))):
        if not rect:
            continue
        x, y, w, h = _crop_px(roi, src_w, src_h)
        out.append(f"[s{i}_{k}]crop={w}:{h}:{x}:{y},scale={rect['w']}:{rect['h']}[{name}{i}]")
        out.append(f"[{last}][{name}{i}]overlay={rect['x']}:{rect['y']}[l{i}_{k}]")
        last, k = f"l{i}_{k}", k + 1
    out.append(f"[{last}]setsar=1,format=yuv420p[v{i}]")
    return out


def _transition(prev_role: str, role: str) -> str:
    if prev_role == "hook":
        return "fadewhite"
    if role == "timelapse" or prev_role == "timelapse":
        return "smoothleft"
    return "fade"


def build_command(plan: dict, source: Path, music: Path | None, overlay: OverlayInput, encoder: EncoderChoice,
                  output: Path, music_volume: float = 0.3, game_volume: float = 0.55, loudness: float = -14.0,
                  threads: int | None = None) -> list[str]:
    fps, xfade, total = plan["fps"], plan["xfade"], plan["duration"]
    has_audio = plan["source"]["has_audio"]
    segments = plan["segments"]
    cmd = [FFMPEG, "-hide_banner", "-v", "error", "-y", *encoder.global_args]
    if threads:
        cmd += ["-threads", str(threads)]
    # Each segment is opened twice: video-only (-an) and audio-only (-vn). acrossfade pulls audio eagerly; with a
    # shared input that would also decode every later segment's video early and queue it in memory (3.4 GB peak
    # measured for a 10-segment recap, 1.5 GB with separate inputs).
    def seek(seg: dict) -> list[str]:
        return ["-ss", f"{seg['src_start']:.3f}", "-t", f"{seg['src_end'] - seg['src_start']:.3f}"]

    n = len(segments)
    for seg in segments:
        cmd += [*seek(seg), "-an", "-i", str(source)]
    audio_base = n
    if has_audio:
        for seg in segments:
            cmd += [*seek(seg), "-vn", "-i", str(source)]
    next_idx = n * (2 if has_audio else 1)
    music_idx = overlay_idx = None
    if music is not None:
        music_idx, next_idx = next_idx, next_idx + 1
        cmd += ["-i", str(music)]
    if overlay.kind == "png_sequence":
        overlay_idx = next_idx
        cmd += ["-framerate", str(fps), "-start_number", str(overlay.start_number), "-i", overlay.path]

    graph: list[str] = []
    for i, seg in enumerate(segments):
        out_dur = seg["out_end"] - seg["out_start"]
        graph.append(f"[{i}:v]setpts=(PTS-STARTPTS)/{seg['speed']},fps={fps},"
                     f"tpad=stop_mode=clone:stop_duration=0.2,trim=duration={out_dur:.4f},setpts=PTS-STARTPTS[s{i}]")
        graph += _layout_chain(i, plan)
        if has_audio and seg["speed"] == 1:
            graph.append(f"[{audio_base + i}:a]asetpts=PTS-STARTPTS,aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,"
                         f"apad,atrim=duration={out_dur:.4f}[a{i}]")
        else:  # time-lapse / slow motion: game audio would be garbled, the music carries it
            graph.append(f"aevalsrc=0|0:c=stereo:s=48000:d={out_dur:.4f},aformat=sample_fmts=fltp[a{i}]")

    vlast, alast = "v0", "a0"
    for i in range(1, n):
        offset = segments[i]["out_start"]
        kind = _transition(segments[i - 1]["role"], segments[i]["role"])
        graph.append(f"[{vlast}][v{i}]xfade=transition={kind}:duration={xfade}:offset={offset:.4f}[vx{i}]")
        graph.append(f"[{alast}][a{i}]acrossfade=d={xfade}:c1=tri:c2=tri[ax{i}]")
        vlast, alast = f"vx{i}", f"ax{i}"

    if overlay.kind == "png_sequence":
        graph.append(f"[{overlay_idx}:v]format=rgba,setpts=PTS-STARTPTS[ov]")
        graph.append(f"[{vlast}][ov]overlay=0:0:eof_action=pass:format=auto[vo]")
        vlast = "vo"
    elif overlay.kind == "ass":
        graph.append(f"[{vlast}]subtitles=filename={overlay.path}:fontsdir={overlay.fonts_dir}[vo]")
        vlast = "vo"
    graph.append(f"[{vlast}]{encoder.pre_filter}[vout]")

    graph.append(f"[{alast}]volume={game_volume}[game]")
    if music_idx is not None:
        graph.append(f"[{music_idx}:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,"
                     f"atrim=duration={total:.4f},asetpts=PTS-STARTPTS,volume={music_volume},"
                     f"afade=t=in:d=0.3,afade=t=out:st={max(0.0, total - 1.5):.4f}:d=1.5[music]")
        graph.append("[game][music]amix=inputs=2:duration=first:normalize=0[mix]")
        mix = "mix"
    else:
        mix = "game"
    graph.append(f"[{mix}]loudnorm=I={loudness}:TP=-1.5:LRA=11,aresample=48000[aout]")

    cmd += ["-filter_complex", ";".join(graph), "-map", "[vout]", "-map", "[aout]",
            "-c:v", encoder.name, *encoder.args]
    if encoder.name != "h264_vaapi":
        cmd += ["-pix_fmt", "yuv420p"]
    cmd += ["-r", str(fps), "-g", str(fps * 2), "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
            "-t", f"{total:.4f}", "-movflags", "+faststart", str(output)]
    return cmd
