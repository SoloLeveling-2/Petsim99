# PS99 Video Studio

Turns a Pet Simulator 99 **VyHub Auto Ranking** recording into professionally edited
1080×1920 YouTube Shorts and TikTok videos, with every number on screen verified from
the footage itself. Runs on your own computer; your original recording is never modified
and nothing is posted unless you connect an account and run `publish` for a video you authorized.

```
recording ─► ingest ─► calibrate (once) ─► analyze ─► plan ─► render ─► review dashboard ─► package or publish
              read-only   mark HUD regions    stars, quests,   hook, clips,  Remotion overlay   approve / reject,   by hand, or opt-in
              fingerprint                     highlights       post text     + 1 FFmpeg pass    authorize per platform  API upload
```

## What you get per recording

| Edit | Length | Contents |
|---|---|---|
| **Full-run recap** | ~45 s | Hook teaser of the best moment, every verified quest completion in order, time-lapses across quiet stretches, rank-up burst, whole-run total. |
| **Best moment** | ~20 s | Hook plus the strongest 2–3 consecutive events. |

Each edit carries: an animated **star counter** (only stars read on screen and stable for 1 s,
never estimated), **QUEST COMPLETE** call-outs with the quest's name, a live inset of the real
in-game quest panel and star counter as proof, a **run clock** showing how far into the recording
each moment is (cuts and time-lapses stay honest), the **paid-in-gems disclosure** (full card for
3 s, then a permanent badge, plus the first line of every caption), original licensed music,
loudness-normalised audio (−14 LUFS) and platform-specific titles, captions and hashtags.

## Setup (Windows; macOS/Linux are the same with `python3` and `source .venv/bin/activate`)

1. Install **Python 3.10+**, **Node.js 18+** and **FFmpeg** (`winget install Gyan.FFmpeg`), then open a new terminal.
2. In this folder:
   ```bat
   py -m venv .venv
   .venv\Scripts\activate
   pip install -r requirements.txt
   cd remotion && npm ci && cd ..
   python -m studio audit
   ```
   `audit` shows which video encoder will be used. NVIDIA (NVENC), Intel (Quick Sync), AMD (AMF),
   Apple (VideoToolbox) and Linux VAAPI are each tested with a real encode; if none opens it uses
   libx264 on the CPU. On first render Remotion downloads its own headless Chrome (~100 MB).

## Use

```bat
python -m studio find                      :: lists 8–15 minute recordings in Videos, Desktop, Downloads…
python -m studio ingest "C:\Users\you\Videos\VyHub Auto Ranking.mp4"
python -m studio review                    :: opens the dashboard → Calibrate → mark the star counter
                                           :: (the whole "19/40") and the quest panel → Save
python -m studio run "C:\Users\you\Videos\VyHub Auto Ranking.mp4"
python -m studio review                    :: watch, inspect, approve or reject, authorize per platform
python -m studio package <render-id> tiktok   :: only after authorizing: folder with video + caption to upload by hand
```

### Posting from the studio (optional)

One-time setup per platform (details at the top of `studio/publish/youtube.py` and `tiktok.py`):

- **YouTube:** Google Cloud project → enable *YouTube Data API v3* → OAuth consent screen (add yourself
  as a test user) → OAuth client of type *Desktop app* → save its JSON as `credentials\youtube_client.json`.
- **TikTok:** developers.tiktok.com app (Desktop) with Login Kit + Content Posting API (Direct Post),
  scopes `user.info.basic,video.publish`, redirect URI `http://127.0.0.1:8766/callback/` → save
  `{"client_key": "…", "client_secret": "…"}` as `credentials\tiktok_client.json`.

```bat
python -m studio connect youtube           :: sign in once in your browser (tokens stay in credentials\)
python -m studio publish <render-id> youtube_shorts --made-for-kids no --paid-promotion no --dry-run
python -m studio publish <render-id> youtube_shorts --made-for-kids no --paid-promotion no   :: type POST
python -m studio connect tiktok
python -m studio publish <render-id> tiktok --paid-promotion no
```

Platform limits you cannot code around: videos uploaded from an **unverified Google API project** are
locked to private until the project passes YouTube's API audit, and an **unaudited TikTok app** can
only post privately (TikTok may also require the account itself to be private). The upload still
works; you change visibility in the app, or apply for the audits.

`run` refuses to count anything until the recording is calibrated (exit code 2), because a
counter that reads the wrong part of the screen would be worse than no counter.

Useful options: `--threads N` (CPU cap for analysis), `--concurrency 1` (Remotion RAM),
`--encoder h264_nvenc` (prefer a GPU encoder), `--overlay ass` (no Node needed, simpler
animation), `--variants recap`, `--research research\vidiq.json` (keywords from vidIQ).

## Safety rules built into the code

- **Originals are read-only.** Recordings are only ever FFmpeg inputs; outputs next to the original are
  refused; size/mtime are checked after every step and the full SHA-256 after every render
  (`python -m studio verify-source <id>` re-checks on demand).
- **Publishing is opt-in and gated.** Nothing contacts YouTube or TikTok until you run `connect` and
  then `publish`. `publish` refuses without a valid authorization, re-hashes the bytes it uploads
  against what you authorized, makes you choose the audience/paid-promotion settings, shows what will be
  posted and waits for you to type `POST` (`--dry-run` posts nothing). Each post is recorded in the
  review history and the same video is never posted twice to a platform unless you pass `--again`.
  Credentials live in the git-ignored `credentials\` folder. Metricool and other services are never called.
- **Approvals are bound to bytes.** Approving stores the SHA-256 of the video and of the post text;
  any change marks the edit **stale** and voids its authorizations.
- **Authorization is per video, per platform**, needs four confirmations (watched it, checked the
  text, checked the disclosure, checked the music license) and typing `AUTHORIZE`.
- **Spending is opt-in.** The only paid call in the code is the optional Claude vision double-check
  (`--vision`, capped by `--vision-budget`, shows the estimated cost and asks first).
- **Disclosure is enforced.** Renders fail validation if any caption lacks the paid-in-gems disclosure.
- **Blocked promotion terms.** `brand/brand.json → blocked_terms` is checked against every generated
  text. Add the previous event script's exact name there.
- **Music needs a license record.** The default track is generated by `studio/music.py` (original,
  you own it). Add other tracks to `music/library.json` with license, proof and allowed platforms.

## Customise the template

`brand/brand.json`: channel name and `handle` (shown on the outro), colours, font, hook and title
templates (`{stars}`, `{quests}`, `{minutes}`), hashtags, disclosure wording, CTA, edit variants
(length, clip padding, time-lapse speed), music levels. Animated components live in
`remotion/src/components`; preview them with `cd remotion && npm run studio`.

## Using vidIQ, Metricool and Descript

These are MCP connectors for Claude Code, not part of this pipeline. From a Claude Code session on
your computer (where they can reach the internet), sign in with `/mcp`, then ask Claude to run keyword
research and save it as `research/vidiq.json` (`{"source": "vidIQ", "fetched_at": "...", "keywords":
[{"keyword": "...", "score": 70}]}`), or to pull Metricool analytics. vidIQ credits, Descript minutes and
any Metricool scheduling are used only when you approve that exact action.

## Tests

```bat
python -m pytest            :: 83 tests incl. ground-truth analysis, renders and Playwright dashboard tests
```

See `docs/TEST_RESULTS.md` for the latest evidence and `docs/TOOL_AUDIT.md` for the tool audit.
