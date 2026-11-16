#!/usr/bin/env python3
"""Prog8 -> x16net.bin -> complete emulator -> loopback TCP integration."""
import argparse
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time

ROOT=Path(__file__).resolve().parents[1]
PREFIX=bytes([0,255,43,13,10,43,43,43])
EXPECTED=PREFIX+bytes(range(256))*16
INITIAL=bytes(reversed(range(256)))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--fragment",type=int,default=17)
    parser.add_argument("--delay",type=float,default=.001)
    args=parser.parse_args()
    if not 1<=args.fragment<=4096 or not 0<=args.delay<=.05:
        parser.error("fragment/delay outside fixture bounds")
    errors=[]
    received=bytearray()
    stop=threading.Event()
    listener=socket.socket()
    listener.bind(("127.0.0.1",0)); listener.listen(1); listener.settimeout(15)
    port=listener.getsockname()[1]

    def chunks(peer,data):
        for i in range(0,len(data),args.fragment):
            if stop.is_set(): return
            peer.sendall(data[i:i+args.fragment])
            if args.delay: time.sleep(args.delay)

    def serve():
        try:
            with listener:
                peer,_=listener.accept()
                with peer:
                    peer.settimeout(15)
                    peer.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
                    chunks(peer,INITIAL)
                    while len(received)<len(EXPECTED):
                        data=peer.recv(min(4096,len(EXPECTED)-len(received)))
                        if not data: raise RuntimeError("guest closed before fixture received all bytes")
                        received.extend(data)
                        chunks(peer,data)
                    if bytes(received)!=EXPECTED:
                        raise RuntimeError("host received different bytes from Prog8 guest")
        except Exception as exc:
            if not stop.is_set(): errors.append(exc)

    thread=threading.Thread(target=serve,daemon=True)
    thread.start()
    try:
        image=(ROOT/"build/network_test.prg").read_bytes()
        address=int.from_bytes(image[:2],"little")
        launcher=re.search(rb"\x9e\s*(\d+)",image[2:40])
        if address!=0x801 or not launcher:
            raise RuntimeError("unexpected Prog8 launcher")
        marker=b"127.0.0.1:00000"
        if image.count(marker)!=1:
            raise RuntimeError("network test endpoint is missing/ambiguous")
        image=image.replace(marker,f"127.0.0.1:{port:05}".encode())
        commands=[f"STM {address+i:04X} {v:02X}" for i,v in enumerate(image[2:])]
        commands.append(f"RUN {int(launcher.group(1)):04X}")
        with tempfile.TemporaryDirectory(prefix="x16net-network-") as dirname:
            shutil.copyfile(ROOT/"build/x16net.bin",Path(dirname)/"x16net.bin")
            result=subprocess.run([
                os.environ["X16EMU"],"-rom",os.environ["X16ROM"],"-serialcard",
                "-testbench","-echo","raw","-sound","none","-warp","-fsroot",dirname],
                input="\n".join(commands)+"\n",text=True,encoding="latin1",
                stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90,
                env=dict(os.environ,SDL_VIDEODRIVER="dummy",SDL_AUDIODRIVER="dummy"))
        output=result.stdout.replace("\r\n","\n").replace("\r","\n")
        (ROOT/"build/network-emulator.log").write_text(output,encoding="utf-8")
        if "# TAP BEGIN\n" not in output:
            raise RuntimeError("no guest TAP marker: "+output[-3000:])
        tap=output.split("# TAP BEGIN\n",1)[1]
        # Keep the plan explicit: no substring-only success checks.
        lines=[line for line in tap.splitlines()
               if line.startswith(("ok ","not ok ","1..","Bail out!"))]
        print("\n".join(lines))
        numbers=[int(m.group(1)) for line in lines if (m:=re.match(r"^ok (\d+) - ",line))]
        if result.returncode or numbers!=list(range(1,9)) or "1..8" not in lines or any(
                line.startswith(("not ok ","Bail out!")) for line in lines):
            raise RuntimeError("network guest failed: "+tap[-3000:])
        thread.join(2)
        if thread.is_alive(): raise RuntimeError("fixture did not complete")
        if errors: raise errors[0]
        if bytes(received)!=EXPECTED: raise RuntimeError("host-side byte verification failed")
        print(f"# host verified {len(received)} transmitted bytes; fragment={args.fragment}, delay={args.delay}")
    finally:
        stop.set()
        listener.close()
        thread.join(2)

if __name__=="__main__":
    try:
        main()
    except Exception as exc:
        print(f"Bail out! network integration: {exc}")
        raise SystemExit(1)
