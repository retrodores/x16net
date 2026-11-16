#!/usr/bin/env python3
"""Execute the real Prog8 Gopher core and x16net binary through the emulator."""
import os,re,shutil,socket,subprocess,tempfile,threading,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
payload=bytes(range(256))*8
listener=socket.socket(); listener.bind(('127.0.0.1',0)); listener.listen(4); listener.settimeout(.2)
port=listener.getsockname()[1]
seen=[]; errors=[]; stopped=threading.Event()

def serve():
    try:
        while not stopped.is_set():
            try: conn,_=listener.accept()
            except socket.timeout: continue
            with conn:
                conn.settimeout(10); request=b''
                while not request.endswith(b'\r\n'):
                    part=conn.recv(1)
                    if not part or len(request)>512: raise AssertionError('bad request framing')
                    request+=part
                seen.append(request)
                if request==b'\r\n':
                    data=(f'0Text\t/text\t127.0.0.1\t{port}\r\n'
                          f'1Menu\t/\t127.0.0.1\t{port}\r\n'
                          f'7Search\t/search\t127.0.0.1\t{port}\r\n'
                          f'9Binary\t/binary\t127.0.0.1\t{port}\r\n'
                          'iInformation\tfake\tignored\t0\r\n'
                          '3Server message\tfake\tignored\t0\r\n.\r\n').encode()
                elif request==b'/text\r\n': data=b'..dot\r\nhello\r\n.\r\n'
                elif request==b'/search\tneedle\r\n': data=f'9Found\t/binary\t127.0.0.1\t{port}\r\n.\r\n'.encode()
                elif request==b'/binary\r\n': data=payload
                elif request==b'/large\r\n': data=b'x'*9000+b'\r\n.\r\n'
                elif request==b'/missing-dot\r\n': data=b'partial text\r\n'
                elif request==b'/bad-menu\r\n': data=b'1Missing fields\r\n1Bad port\t/\thost\t65536\r\n1Bad host\t/\t\t70\r\n.\r\n'
                else: raise AssertionError(f'unexpected selector: {request!r}')
                # Fragment headers, tabs, CRLF, and payload rather than relying on recv boundaries.
                for pos in range(0,len(data),17):
                    try: conn.sendall(data[pos:pos+17])
                    except (BrokenPipeError,ConnectionResetError):
                        if request!=b'/large\r\n': raise
                        break
                    time.sleep(.0002)
    except Exception as exc:
        if not stopped.is_set(): errors.append(exc)
thread=threading.Thread(target=serve,daemon=True);thread.start()
try:
    image=(ROOT/'build/gopher_test.prg').read_bytes()
    marker=b'127.0.0.1:00000'; assert image.count(marker)==1
    image=image.replace(marker,f'127.0.0.1:{port:05}'.encode())
    address=int.from_bytes(image[:2],'little'); entry=re.search(rb'\x9e\s*(\d+)',image[2:40])
    assert entry and address==0x801
    commands=[f'STM {address+i:04X} {v:02X}' for i,v in enumerate(image[2:])]
    commands.append(f'RUN {int(entry.group(1)):04X}')
    with tempfile.TemporaryDirectory(prefix='x16-gopher-') as tmp:
        shutil.copyfile(ROOT/'build/x16net.bin',Path(tmp)/'x16net.bin')
        run=subprocess.run([os.environ['X16EMU'],'-rom',os.environ['X16ROM'],'-serialcard','-testbench',
            '-echo','raw','-sound','none','-warp','-fsroot',tmp],input='\n'.join(commands)+'\n',
            cwd=tmp,text=True,encoding='latin1',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120,
            env=dict(os.environ,SDL_VIDEODRIVER='dummy',SDL_AUDIODRIVER='dummy'))
        output=run.stdout.replace('\r','\n'); (ROOT/'build/gopher-emulator.log').write_text(output)
        assert '# GOPHER TAP BEGIN' in output,output[-2000:]
        lines=[s for s in output.split('# GOPHER TAP BEGIN',1)[1].splitlines() if s.startswith(('ok ','not ok ','1..','# status'))]
        print('\n'.join(lines),flush=True)
        assert run.returncode==0 and len([s for s in lines if s.startswith('ok ')])==11 and '1..11' in lines
        assert not any(s.startswith('not ok ') for s in lines)
        assert (Path(tmp)/'gopher-test.bin').read_bytes()==payload,'download differs from source bytes'
    assert not errors,errors
    assert seen==[b'\r\n',b'/text\r\n',b'/search\tneedle\r\n',b'/binary\r\n',b'/large\r\n',b'/missing-dot\r\n',b'/bad-menu\r\n'],seen
    print('# Host verified selectors, search, file bytes and overwrite protection')
finally:
    stopped.set(); listener.close(); thread.join(3)
