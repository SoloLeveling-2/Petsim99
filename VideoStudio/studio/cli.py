"""Command line: python -m studio <command>. Run `python -m studio --help` for the list."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shutil
import sys
import webbrowser
from pathlib import Path

from . import __version__
from .config import WORKSPACE, load_brand
from .media import FFMPEG, MediaError, run


def _print(*lines: str) -> None:
    print("\n".join(lines), flush=True)


def _workspace(args):
    from .workspace import Workspace

    return Workspace(Path(args.workspace))


def _resolve_source(ws, ref: str) -> str:
    """Accept a source id or a path to a recording (registered on the fly)."""
    if Path(ref).is_file():
        return ws.register(Path(ref))["id"]
    ws.source_dir(ref)
    return ref


# --- audit -------------------------------------------------------------------------------
def cmd_audit(args) -> int:
    from .hwaccel import ENCODER_PRIORITY, choose_encoder, probe_encoders
    from .music import load_library, validate_track
    from .render.remotion_overlay import REMOTION_DIR, remotion_available

    rows = []
    try:
        version = run([FFMPEG, "-hide_banner", "-version"]).stdout.splitlines()[0]
        rows.append(("FFmpeg", "ok", version))
    except (MediaError, OSError) as exc:
        rows.append(("FFmpeg", "MISSING", str(exc)))
    available = probe_encoders()
    usable = [n for n in ENCODER_PRIORITY if available.get(n)]
    best = choose_encoder(available).name if usable else "none"
    rows.append(("Video encoders", "ok" if usable else "MISSING",
                 f"working: {', '.join(usable) or 'none'}; will use {best}"
                 + ("" if any(available.get(n) for n in ENCODER_PRIORITY[:-1]) else " (no GPU encoder opened on this machine)")))
    ocr = importlib.util.find_spec("rapidocr") is not None
    rows.append(("RapidOCR", "ok" if ocr else "MISSING", "offline text reading" if ocr else "pip install -r requirements.txt"))
    rows.append(("OpenCV", "ok" if importlib.util.find_spec("cv2") else "MISSING", "frame analysis"))
    rows.append(("Remotion", "ok" if remotion_available() else "not installed",
                 f"branded overlay ({REMOTION_DIR})" if remotion_available()
                 else f"run `npm ci` in {REMOTION_DIR}; the simpler ASS overlay is used meanwhile"))
    tracks = load_library()
    valid = [t["id"] for t in tracks if not validate_track(t, require_file=False)]
    rows.append(("Music library", "ok" if valid else "EMPTY", f"licensed tracks: {', '.join(valid)}"))
    has_sdk = importlib.util.find_spec("anthropic") is not None
    key = "set" if os.environ.get("ANTHROPIC_API_KEY") else "not set"
    rows.append(("Claude vision", "optional", f"anthropic package {'installed' if has_sdk else 'not installed'}; "
                                              f"ANTHROPIC_API_KEY {key}; only used with --vision (costs credits)"))
    rows.append(("vidIQ / Metricool / Descript", "via Claude Code",
                 "MCP connectors are used from a Claude Code session (/mcp to sign in); the studio never calls them"))
    width = max(len(r[0]) for r in rows)
    _print(f"PS99 Studio {__version__} audit", *(f"  {n.ljust(width)}  [{s}]  {d}" for n, s, d in rows))
    return 0 if all(s not in ("MISSING",) for _, s, _ in rows) else 1


# --- find / ingest -----------------------------------------------------------------------
def cmd_find(args) -> int:
    from .discover import default_roots, find_recordings

    roots = [Path(r) for r in args.root] if args.root else default_roots()
    _print("Searching: " + ", ".join(str(r) for r in roots))
    found = find_recordings(roots, args.min_minutes * 60, args.max_minutes * 60)
    if not found:
        _print("No recordings in that length range. Pass --root <folder> or widen --min-minutes/--max-minutes.")
        return 1
    for c in found:
        _print(f"{c.duration / 60:5.1f} min  {c.size / 1e6:8.1f} MB  {c.path}", f"           {'; '.join(c.reasons)}")
    return 0


def cmd_ingest(args) -> int:
    ws = _workspace(args)
    record = ws.register(Path(args.path))
    calibrated = ws.profile(record["id"]).calibrated
    _print(f"Registered (read-only): {record['path']}",
           f"  {record['info']['duration'] / 60:.1f} min, {record['info']['width']}x{record['info']['height']} "
           f"@ {record['info']['fps']} fps, sha256 {record['fingerprint']['sha256'][:16]}…",
           "  Calibrated: " + ("yes" if calibrated else "no - open the dashboard (python -m studio review) → Calibrate"),
           f"Source id: {record['id']}")
    return 0


# --- analyze / plan / render ---------------------------------------------------------------
def _progress(t: float, total: float) -> None:
    print(f"\r  analysing… {min(100, 100 * t / max(total, 1e-6)):5.1f}%", end="", flush=True)


def cmd_analyze(args) -> int:
    from .analyze import analyze_source
    from .vision import estimate_cost

    ws = _workspace(args)
    sid = _resolve_source(ws, args.source)
    profile = ws.profile(sid)
    budget = 0
    if args.vision:
        budget = args.vision_budget
        est = estimate_cost(budget)
        _print(f"Claude vision will check up to {budget} star changes with {est['model']} "
               f"(estimated ≤ ${est['usd']:.2f} of API credits).")
        if not args.yes:
            if input("Spend up to that amount? Type yes to continue: ").strip().lower() != "yes":
                _print("Vision check skipped.")
                budget = 0
    result = analyze_source(Path(ws.source(sid)["path"]), profile, ws.analysis_dir(sid), sample_fps=args.fps,
                            threads=args.threads, vision=budget > 0, vision_budget=budget, progress=_progress)
    t = result["totals"]
    _print("", f"Analysed {result['source']['duration'] / 60:.1f} min in {result['stats']['seconds']} s "
               f"({result['stats']['ocr_calls_star']} counter reads, {result['stats']['ocr_calls_panel']} panel reads).",
           f"  Rank stars counted on screen: {t['stars_verified'] if t['stars_verified'] is not None else 'n/a (not calibrated)'}",
           f"  Quests: {t['quests_confirmed']} confirmed, {t['quests_probable']} probable · rank ups: {t['rank_ups']} · "
           f"needs review: {t['review_items']}",
           *(f"  ! {w}" for w in result["warnings"]))
    return 0


def _plans(ws, sid: str, variants: list[str], research_path: str | None) -> list[tuple[dict, Path]]:
    from .metadata import build_metadata, validate_metadata
    from .music import ensure_track_file, load_library, pick_track
    from .planner import plan_variant

    brand = load_brand()
    analysis = json.loads((ws.analysis_dir(sid) / "analysis.json").read_text(encoding="utf-8"))
    research = json.loads(Path(research_path).read_text(encoding="utf-8")) if research_path else None
    track = pick_track(load_library(), ["youtube_shorts", "tiktok"], prefer=brand["music"]["default_track"])
    ensure_track_file(track)
    out = []
    for variant in brand["variants"]:
        if variants and variant["id"] not in variants:
            continue
        plan = plan_variant(analysis, brand, variant)
        plan["music"] = {k: track.get(k) for k in ("id", "title", "file", "license", "license_type", "proof",
                                                   "attribution_required")}
        plan["metadata"] = build_metadata(analysis, plan, brand, research)
        problems = validate_metadata(plan["metadata"], brand)
        if problems:
            raise MediaError("Post text failed validation: " + "; ".join(problems))
        path = ws.source_dir(sid) / "plans" / f"{variant['id']}.json"
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(plan, indent=1), encoding="utf-8")
        out.append((plan, path))
    return out


def cmd_plan(args) -> int:
    ws = _workspace(args)
    sid = _resolve_source(ws, args.source)
    for plan, path in _plans(ws, sid, args.variants.split(",") if args.variants else [], args.research):
        _print(f"{plan['variant']}: {plan['duration']:.1f} s, {len(plan['segments'])} segments, "
               f"{len(plan['overlay']['quests'])} quest pops → {path}",
               f"  YouTube title: {plan['metadata']['youtube_shorts']['title']}")
    return 0


def _render(ws, sid: str, plan: dict, args) -> dict:
    from .hwaccel import choose_encoder, probe_encoders
    from .render.run import render_plan
    from .review.events import review_events

    encoder = None
    if args.encoder:
        encoder = choose_encoder(probe_encoders(), prefer=args.encoder)
    rdir = ws.new_render_dir(sid, plan["variant"])
    manifest = render_plan(plan, rdir, overlay=args.overlay, encoder=encoder, concurrency=args.concurrency,
                           metadata=plan["metadata"])
    analysis = json.loads((ws.analysis_dir(sid) / "analysis.json").read_text(encoding="utf-8"))
    manifest["facts"] = plan["metadata"]["youtube_shorts"]["facts"]
    manifest["events"] = review_events(analysis, plan, ws.analysis_dir(sid), rdir)
    manifest["warnings"] += analysis["warnings"]
    (rdir / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    _print(f"  ✓ {manifest['id']}: {manifest['video']['duration']:.1f} s, {manifest['encoder']['name']}, "
           f"{manifest['overlay_engine']} overlay, {manifest['render_seconds']} s")
    return manifest


def cmd_render(args) -> int:
    ws = _workspace(args)
    sid = _resolve_source(ws, args.source)
    wanted = [] if args.variant == "all" else [args.variant]
    plans = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((ws.source_dir(sid) / "plans").glob("*.json"))
             if not wanted or p.stem in wanted]
    if not plans:
        _print("No plan yet: run `python -m studio plan <source>` first.")
        return 1
    for plan in plans:
        _render(ws, sid, plan, args)
    _print("Review them: python -m studio review")
    return 0


def cmd_run(args) -> int:
    ws = _workspace(args)
    sid = ws.register(Path(args.path))["id"]
    if not ws.profile(sid).calibrated and not args.uncalibrated_ok:
        _print(f"Registered {args.path} as {sid}, but it is not calibrated yet, so stars and quests cannot be counted.",
               "Calibrate once: python -m studio review  → Calibrate → mark the star counter and quest panel → Save.",
               "Then run this command again. (Use --uncalibrated-ok to render activity-only edits without counters.)")
        return 2
    ns = argparse.Namespace(**{**vars(args), "source": sid, "fps": None, "threads": None})
    cmd_analyze(ns)
    for plan, _ in _plans(ws, sid, args.variants.split(",") if args.variants else [], args.research):
        _render(ws, sid, plan, args)
    _print("Done. Review, approve and authorize: python -m studio review")
    return 0


# --- review / package / misc ------------------------------------------------------------------
def cmd_review(args) -> int:
    from .review.server import make_server

    httpd, _ = make_server(Path(args.workspace), port=args.port)
    url = f"http://127.0.0.1:{httpd.server_address[1]}/"
    _print(f"Review dashboard: {url}  (local only; Ctrl+C to stop)")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


def cmd_package(args) -> int:
    from .review.store import ReviewError, ReviewStore

    try:
        out = ReviewStore(Path(args.workspace)).package(args.render_id, args.platform)
    except ReviewError as exc:
        _print(f"Not packaged: {exc}. Approve and authorize this platform in the dashboard first.")
        return 1
    _print(f"Ready to upload by hand: {out}", "  final.mp4, caption.txt, post.json, AUTHORIZATION.json",
           "Nothing was uploaded.")
    return 0


def cmd_verify_source(args) -> int:
    ws = _workspace(args)
    sid = _resolve_source(ws, args.source)
    ws.guard(sid).verify(full=True)
    _print(f"Unchanged: {ws.source(sid)['path']} (SHA-256 matches the registered fingerprint)")
    return 0


def cmd_music(args) -> int:
    from .music import ensure_track_file, load_library, validate_track

    for track in load_library():
        problems = validate_track(track, require_file=False)
        if args.action == "generate" and not problems:
            path = ensure_track_file(track)
            _print(f"{track['id']}: {path}")
        else:
            _print(f"{track['id']}: {'OK' if not problems else 'INVALID - ' + '; '.join(problems)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m studio", description="PS99 Auto Ranking video studio")
    p.add_argument("--workspace", default=str(WORKSPACE), help="where analyses and renders are stored")
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("audit", help="check tools, encoders, OCR, Remotion, music, credentials")
    f = sub.add_parser("find", help="find candidate recordings on this computer")
    f.add_argument("--root", action="append", help="folder to search (repeatable); default: Videos, Desktop, …")
    f.add_argument("--min-minutes", type=float, default=8)
    f.add_argument("--max-minutes", type=float, default=15)
    i = sub.add_parser("ingest", help="register a recording (read-only)")
    i.add_argument("path")

    def add_vision(sp):
        sp.add_argument("--vision", action="store_true", help="ask Claude to double-check star changes (costs credits)")
        sp.add_argument("--vision-budget", type=int, default=20, help="max star changes sent to Claude")
        sp.add_argument("--yes", action="store_true", help="skip the spending confirmation prompt")

    def add_render_opts(sp):
        sp.add_argument("--overlay", choices=["auto", "remotion", "ass"], default="auto")
        sp.add_argument("--encoder", help="prefer this encoder, e.g. h264_nvenc (falls back if unavailable)")
        sp.add_argument("--concurrency", type=int, default=2, help="Remotion browser tabs (RAM vs speed)")

    a = sub.add_parser("analyze", help="find star gains, quest completions and highlights")
    a.add_argument("source", help="source id or recording path")
    a.add_argument("--fps", type=float, help="samples per second (default from profile, 2)")
    a.add_argument("--threads", type=int, help="CPU threads for decoding/OCR (default: half the cores)")
    add_vision(a)
    pl = sub.add_parser("plan", help="build edit plans and post text")
    pl.add_argument("source")
    pl.add_argument("--variants", help="comma list, e.g. recap,highlight (default: all in brand.json)")
    pl.add_argument("--research", help="JSON with vidIQ keyword research to use for tags")
    r = sub.add_parser("render", help="render planned edits to 1080x1920 MP4")
    r.add_argument("source")
    r.add_argument("--variant", default="all")
    add_render_opts(r)
    rn = sub.add_parser("run", help="ingest + analyze + plan + render")
    rn.add_argument("path")
    rn.add_argument("--variants")
    rn.add_argument("--research")
    rn.add_argument("--uncalibrated-ok", action="store_true")
    add_vision(rn)
    add_render_opts(rn)
    rv = sub.add_parser("review", help="open the local review dashboard")
    rv.add_argument("--port", type=int, default=8765)
    rv.add_argument("--no-browser", action="store_true")
    pk = sub.add_parser("package", help="prepare an AUTHORIZED render for manual upload (uploads nothing)")
    pk.add_argument("render_id")
    pk.add_argument("platform", choices=["youtube_shorts", "tiktok"])
    vs = sub.add_parser("verify-source", help="prove the original recording is unchanged (full SHA-256)")
    vs.add_argument("source")
    m = sub.add_parser("music", help="check or generate the licensed music library")
    m.add_argument("action", choices=["check", "generate"])
    return p


COMMANDS = {"audit": cmd_audit, "find": cmd_find, "ingest": cmd_ingest, "analyze": cmd_analyze, "plan": cmd_plan,
            "render": cmd_render, "run": cmd_run, "review": cmd_review, "package": cmd_package,
            "verify-source": cmd_verify_source, "music": cmd_music}


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return COMMANDS[args.command](args)
    except (MediaError, ValueError, FileNotFoundError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
