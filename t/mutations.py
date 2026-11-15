#!/usr/bin/env python3
"""Prove the binary suite rejects representative regressions; restore on exit."""
from pathlib import Path
import re
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]
binary = ROOT / "build/x16net.bin"
original = binary.read_bytes()
symbols = {}
for line in (ROOT/"build/x16net.labels").read_text().splitlines():
    m = re.match(r"(\w+)\s*=\s*\$([0-9a-fA-F]+)", line)
    if m:
        symbols[m[1]]=int(m[2],16)-0x8000
mutations = [
    ("ABI magic", 36, original[36]^1),
    ("baud divisor", symbols["divisors"]+4, 16),
    ("UART writes disabled", symbols["uart_store"], 0xad),
    ("receive carry inverted", symbols["rx_available"]+5, 0x38),
    ("quiet mode disabled", symbols["dial_command"]+3, ord("0")),
    ("hangup never deasserts DTR", symbols["disconnect"] +
     original[symbols["disconnect"]:symbols["disconnect_wait"]].index(b"\xa9\x26")+1, 0x27),
]
failed = False
try:
    for i,(name,offset,value) in enumerate(mutations,1):
        mutant=bytearray(original)
        mutant[offset]=value
        binary.write_bytes(mutant)
        p=subprocess.run([sys.executable,"t/test_binary.py"],cwd=ROOT,
                         stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
        (ROOT/f"build/mutation-{i}.tap").write_bytes(p.stdout)
        caught=p.returncode != 0 and b"not ok" in p.stdout
        print(f"{'ok' if caught else 'not ok'} {i} - rejects {name}")
        failed |= not caught
finally:
    binary.write_bytes(original)
print(f"1..{len(mutations)}")
sys.exit(failed)
