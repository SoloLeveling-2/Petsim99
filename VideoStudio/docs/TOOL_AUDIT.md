# Tool and connector audit — 2026-10-12

Audited from the Claude Code cloud session that built this pipeline (Linux container,
4 vCPU, 15 GiB RAM, **no GPU**). Every row was checked by running something, not by
reading configuration alone. "Authenticated" means a call that requires the account
succeeded; nothing here was assumed from an install message.

| Tool | Installed | Reachable from this session | Authenticated | How it is used by the pipeline |
|---|---|---|---|---|
| FFmpeg 6.1.1 / FFprobe | yes (`/usr/bin`) | n/a (local) | n/a | Decoding, ROI sampling, cutting, layout, mixing, encoding. This Ubuntu build includes NVENC, QSV and VAAPI encoders (not AMF), plus libass, xfade and loudnorm. |
| Hardware video encode/decode | encoders compiled in | **no device**: no `/dev/dri`, no `nvidia-smi` | n/a | `studio hw` probes each encoder with a real 1-frame test encode on *your* machine and falls back to libx264. Not verifiable here. |
| OpenCV | `opencv-python-headless 5.0.0.93` (installed in venv) | n/a | n/a | Frame differencing, ROI change detection, colour/activity scoring, synthetic test fixture. |
| OCR (RapidOCR 3.10 + onnxruntime 1.31) | yes, models bundled in wheel | works offline | n/a | Reads the on-screen rank-star counter and quest-panel text. ~17 ms per crop on CPU. |
| Claude vision (in-session) | yes | yes | yes (this session) | Used during the build to inspect rendered frames (see TEST_RESULTS.md). |
| Claude vision (pipeline, via API) | code path present | `api.anthropic.com` reachable | **no `ANTHROPIC_API_KEY`** | Optional `--vision` verification of candidate events. Off by default because it costs money; never runs without the flag. |
| Remotion 4.0.534 | npm project in `VideoStudio/remotion` (verified: overlay rendered and composited) | npm registry reachable | n/a | Renders the branded animated overlay (transparent PNG sequence). Uses the preinstalled Chromium here; downloads its own on your machine. |
| vidIQ MCP (plugin 0.1.6) | plugin installed | **blocked** — `mcp.vidiq.com` refused by the environment network policy (HTTP 403 on CONNECT) | **not verified** (OAuth never reached) | Research input file `research/vidiq.json`; titles/tags fall back to unvalidated defaults and say so. |
| Metricool MCP | server added (`claude mcp add`) | **blocked** — `ai.metricool.com` refused (403) | **not verified** | Analytics/platform management not available. Dashboard publication authorizations are recorded only; nothing is sent. |
| Descript MCP (plugin 1.1.0) | plugin installed | **blocked** — `api.descript.com` refused (403) | **not verified** (OAuth + Drive selection required) | Optional; not used. The pipeline does not need it for the current edit style. |
| Context7 | claude.ai connector **connected**; plugin copy blocked | yes via connector | yes | Used to check current Remotion CLI documentation during the build. |
| Playwright | plugin installed (MCP `npx @playwright/mcp`, connected); Python `playwright 1.56.0` | Chromium 141 preinstalled | n/a | Dashboard end-to-end tests (`tests/e2e`). |
| Superpowers 6.4.2 | synced + marketplace copy | n/a | n/a | Process: spec, plan, TDD, verification before completion. |
| Exa (web search) | claude.ai connector connected | yes | yes | Not needed so far. |
| Your local computer | — | **no remote-device link in this session** | — | Cannot browse your disk from the cloud. `studio find` runs on your machine instead. |

## Credentials present in this container

None of `ANTHROPIC_API_KEY`, `VIDIQ_*`, `METRICOOL_*`, `DESCRIPT_*`, `YOUTUBE_*`,
`TIKTOK_*` are set. No credential values were printed or stored.

## What it takes to turn the blocked services on

1. **Network**: in the cloud environment settings (title bar → environment → Edit →
   Network access) allow `mcp.vidiq.com`, `ai.metricool.com`, `api.descript.com`, or run
   the commands from a Claude Code session on your own computer, where they are not
   proxied.
2. **Sign-in**: vidIQ and Descript use browser OAuth; Metricool's MCP also requires
   signing in to your Metricool account. These must be completed by you; credentials
   are never requested in chat.
3. **Spending**: vidIQ research calls consume vidIQ credits and Descript imports consume
   Descript plan minutes. The pipeline treats both as spending and will not call them
   without your explicit approval of the exact call.

## Source recording

The ~11 minute VyHub Auto Ranking recording is **not** in this container or in any
branch of the repository (`find` across the filesystem and `git ls-tree` of every remote
branch). Run `python -m studio find` on your computer to locate it — see the README.
