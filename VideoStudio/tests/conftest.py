import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

ARTIFACTS = ROOT / "tests" / ".artifacts"


def make_clip(path: Path, seconds: float, size: str = "320x180", audio: bool = True) -> Path:
    """Write a small test-pattern clip with FFmpeg (test helper, not production code)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"testsrc2=size={size}:rate=30:duration={seconds}"]
    if audio:
        cmd += ["-f", "lavfi", "-i", f"sine=frequency=440:sample_rate=48000:duration={seconds}"]
    cmd += ["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p"]
    if audio:
        cmd += ["-c:a", "aac", "-shortest"]
    cmd.append(str(path))
    subprocess.run(cmd, check=True)
    return path


@pytest.fixture(scope="session")
def fixture_video():
    """The synthetic PS99-like recording with ground truth, built once per test session."""
    from tests.fixtures.synth import make_fixture

    out = ARTIFACTS / "fixture"
    info = make_fixture(out)
    return info


@pytest.fixture
def artifacts_dir(request):
    d = ARTIFACTS / request.node.name
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    return d
