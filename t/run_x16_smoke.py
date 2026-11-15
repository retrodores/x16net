#!/usr/bin/env python3
"""Run the compiled Prog8 external-call smoke program on stock x16emu.

No serial card emulation: only loading, ABI version, and uninitialized error ABI.
X16EMU and X16ROM point to a compatible testbench-enabled emulator/ROM pair.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]

def main():
    image=(ROOT/"build/abi_smoke.prg").read_bytes()
    start=int.from_bytes(image[:2],"little")
    launcher=re.search(rb"\x9e\s*(\d+)",image[2:40])
    if start != 0x801 or not launcher:
        raise RuntimeError("unexpected Prog8 PRG launcher")
    commands=[f"STM {start+i:04X} {v:02X}" for i,v in enumerate(image[2:])]
    commands.append(f"RUN {int(launcher.group(1)):04X}")
    env=dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    result=subprocess.run([
        os.environ["X16EMU"],"-rom",os.environ["X16ROM"],
        "-testbench","-echo","raw","-sound","none","-warp",
        "-fsroot",str(ROOT/"build")],
        input="\n".join(commands)+"\n",text=True,encoding="latin1",
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=40,env=env)
    output=result.stdout.replace("\r","")
    marker="# TAP BEGIN\n"
    if marker not in output:
        raise RuntimeError(output[-4000:])
    tap=output.split(marker,1)[1]
    print(tap)
    if result.returncode or "not ok" in tap or "1..2" not in tap:
        raise RuntimeError("X16 ABI smoke failed")
if __name__=="__main__":
    try:
        main()
    except Exception as exc:
        print(f"Bail out! {exc}")
        sys.exit(1)
