#!/usr/bin/env bash
set -euo pipefail
root=.
scratch=/private$TMPDIR/tmp.oNxPyyVT6T
llvm=/opt/homebrew/opt/llvm/bin
out=/tmp/llvm-user-type-gc-trace
mkdir -p "$out"
fixbits=$($LW_ROOT/lg-bin/lg-e9789b7d53 -source-paths "$root/src" "$root/checks/profile-field.lg" host fixnum-bits)
"$llvm/clang" -O2 -w "-DLG_FIXNUM_BITS=$fixbits" -DLG_GC_TRACE -c -emit-llvm "$root/host/native/gc.c" -o "$out/gc.bc"
"$llvm/llvm-link" "$scratch/m.ll" "$scratch/rt.bc" "$out/gc.bc" "$scratch/posix.bc" -o "$out/all.bc"
runner=$(bash "$root/checks/build-orc-runner.sh")
LG_HEAP_BYTES=1048576 "$runner" "$out/all.bc" checks/fixtures/jank-reader/definitions.lg > "$out/combined.log" 2>&1
python3 - "$out" <<'PYINNER'
from pathlib import Path
import sys
out=Path(sys.argv[1])
lines=(out/'combined.log').read_text().splitlines(keepends=True)
traces=[s for s in lines if s.startswith('gc: live ')]
actual=''.join(s for s in lines if not s.startswith('gc: live '))
expected=Path('/private$TMPDIR/tmp.NTEpFoggD1/n.out').read_text()
assert actual == expected, 'Traced execution differs from native output'
end=next(i for i,s in enumerate(lines) if s.strip()=='50159888')
start=max(i for i,s in enumerate(lines[:end]) if s.strip()=='21')
interval=sum(s.startswith('gc: live ') for s in lines[start:end])
assert interval > 1, 'No repeated collection in allocation interval'
print(f'MATCH; {len(traces)} collections total; {interval} collections between the preceding output and allocation-loop result')
PYINNER
