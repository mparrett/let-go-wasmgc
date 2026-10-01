#!/usr/bin/env python3
# host/pty-run.py <cols> <rows> <keys> <cmd...> — run cmd on a pseudo-terminal
# of that size (TIOCSWINSZ), the way native lg's term/* natives need one
# (term/size is nil and read-key cannot go raw off a TTY), send each char of
# <keys> as one keypress once output has been quiet for 0.3 s, and write
# everything the program printed to stdout, raw. The native side of
# corpus/host/term-demo.lg's comparison with host/node-host.mjs (P4.1).
# Exits with the program's status (124 if it had to be killed).
import os, pty, sys, struct, fcntl, termios, time, select
cols, rows, keys = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[4], sys.argv[4:])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
out = bytearray()
def pump(quiet, limit=10.0):
    """read until `quiet` s pass with no output (or EOF / limit); False at EOF"""
    end, last = time.time() + limit, time.time()
    while time.time() < end and time.time() - last < quiet:
        r, _, _ = select.select([fd], [], [], 0.02)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return False
            if not d: return False
            out.extend(d); last = time.time()
    return True
alive = pump(0.5)
for k in keys:
    if not alive: break
    os.write(fd, k.encode()); alive = pump(0.3)
if alive: pump(1.0, 5.0)
code = 124
for _ in range(50):
    p, st = os.waitpid(pid, os.WNOHANG)
    if p: code = os.waitstatus_to_exitcode(st); break
    time.sleep(0.05)
else:
    os.kill(pid, 9); os.waitpid(pid, 0)
sys.stdout.buffer.write(bytes(out))
sys.exit(code)
