#!/usr/bin/env python3
"""Check the shared X16 Gopher renderer against actual emulated VERA memory."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    result = subprocess.run(
        [os.environ["X16EMU"], "-rom", os.environ["X16ROM"], "-prg", str(ROOT / "build/gopher_view_test.prg"), "-run",
         "-echo", "raw", "-sound", "none", "-warp"],
        text=True, encoding="latin1",
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
        env=dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy"),
    )
    output = result.stdout.replace("\r", "\n")
    (ROOT / "build/gopher-display-emulator.log").write_text(output, encoding="utf-8")
    assert "# GOPHER DISPLAY TAP BEGIN" in output, output[-3000:]
    tap = output.split("# GOPHER DISPLAY TAP BEGIN", 1)[1]
    lines = [line for line in tap.splitlines() if line.startswith(("ok ", "not ok ", "1.."))]
    print("\n".join(lines))
    assert result.returncode == 0, result.returncode
    assert len([line for line in lines if line.startswith("ok ")]) == 15, lines
    assert "1..15" in lines and not any(line.startswith("not ok ") for line in lines)


if __name__ == "__main__":
    main()
