#!/usr/bin/env bash
# Warm compute benchmark; run under checks/quiet.sh.
# Emits artifacts plus results.json to the output directory.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
out=${1:-/tmp/llvm-compute-bench}
mkdir -p "$out"
out=$(cd "$out" && pwd)
mkdir -p "$out"
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
bash checks/build-orc-runner.sh > "$out/runner"
fixbits=$("$LG" -source-paths src checks/profile-field.lg host fixnum-bits)
for c in rt gc posix; do
 "$llvm/clang" -O2 -w "-DLG_FIXNUM_BITS=$fixbits" -emit-llvm -c "host/native/$c.c" -o "$out/$c.bc"
done
for name in fib xxh; do
 "$LG" -source-paths src:rt src/driver.lg --target llvm --no-rtlib "checks/fixtures/compute/$name.lg" "$out/$name.ll"
 "$llvm/llvm-link" "$out/$name.ll" "$out/rt.bc" "$out/gc.bc" "$out/posix.bc" -o "$out/$name.bc"
 "$llvm/clang" -O2 -w "$out/$name.bc" -o "$out/$name"
done

python3 - "$out" <<'PY'
import subprocess, pathlib, json, os, time, sys
root=pathlib.Path.cwd()
work=pathlib.Path(sys.argv[1])
runner=(work/'runner').read_text().strip()
lg=os.environ['LG']
env=dict(os.environ,LW_ORC_CACHE_DIR=str(work/'cache'),LW_ORC_STATS='1')
results=[]
for name in ['fib','xxh']:
 source=str(root/'checks/fixtures/compute'/f'{name}.lg')
 commands={'bytecode':[lg,'-source-paths',str(root/'rt'),source], 'aot':[str(work/name)], 'orc':[runner,str(work/f'{name}.bc')]}
 expected=None
 for engine,cmd in commands.items():
  # Seed native objects outside measured samples. Every program also warms 10 calls.
  if engine=='orc':subprocess.run(cmd,env=env,capture_output=True,check=True,timeout=180)
  samples=[]
  for i in range(3):
   start=time.perf_counter()
   r=subprocess.run(cmd,env=env,capture_output=True,text=True,check=True,timeout=180)
   wall=time.perf_counter()-start
   checksum,ns=map(int,r.stdout.split())
   if expected is None:expected=checksum
   assert checksum==expected,(name,engine,checksum,expected)
   if engine=='orc':assert 'hits=1 misses=0' in r.stderr,r.stderr
   samples.append({'compute_ns':ns,'process_seconds':wall,'checksum':checksum,'stderr':r.stderr})
   print(name,engine,i,'compute_ms',ns/1e6,'process_s',wall,flush=True)
  results.append({'workload':name,'engine':engine,'samples':samples})
  (work/'results.json').write_text(json.dumps(results,indent=2)+'\n')
PY
