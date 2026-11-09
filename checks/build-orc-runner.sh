#!/usr/bin/env bash
# Build the isolated executor against the selected installed LLVM.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$root" "${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}" <<'PY'
import hashlib, os, pathlib, shlex, subprocess, sys, tempfile
root, llvm = map(pathlib.Path, sys.argv[1:])
def config(*args):
    return subprocess.check_output([str(llvm/'llvm-config'), *args], text=True).strip()
source = root/'host/native/orc-runner.cpp'
cxx = shlex.split(config('--cxxflags'))
link = shlex.split(config('--ldflags', '--link-shared', '--libs', 'orcjit', 'native', 'passes', '--system-libs'))
libraries = shlex.split(config('--link-shared', '--libfiles', 'orcjit', 'native', 'passes'))
h = hashlib.sha256(source.read_bytes())
for value in [str(root), str(llvm.resolve()), config('--version'), repr(cxx), repr(link)]:
    h.update(value.encode()); h.update(b'\0')
# Include the actual LLVM implementation, not just its version label.
for name in [str(llvm/'clang++'), *libraries]:
    with open(name, 'rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''): h.update(block)
key = h.hexdigest()
directory = pathlib.Path(os.environ.get('LW_ORC_BUILD_DIR', str(root/'src/.orc-tools')))
directory.mkdir(parents=True, exist_ok=True)
output = directory/('orc-runner-'+key)
if not output.is_file():
    fd, temporary = tempfile.mkstemp(prefix='.orc-build-', dir=directory)
    os.close(fd)
    try:
        subprocess.run([str(llvm/'clang++'), *cxx, '-O2',
                        '-DLG_ORC_BUILD_ID="'+key+'"', str(source), '-o', temporary,
                        *link, '-Wl,-rpath,'+config('--libdir')], check=True)
        os.chmod(temporary, 0o755)
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
print(output.resolve())
PY
