#!/usr/bin/env bash
# Run under checks/quiet.sh after bench-llvm-compute.sh prepares artifacts.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
out=${1:-/tmp/llvm-compute-bench}
out=$(cd "$out" && pwd)
mkdir -p "$out/go-xxh"
cp checks/fixtures/compute/go-xxh/main.go "$out/go-xxh/main.go"
cat > "$out/go-xxh/go.mod" <<'MOD'
module benchmark.local/xxh

go 1.27.1

require github.com/zeebo/xxh3 v1.1.0
MOD
cp "$LETGO/go.sum" "$out/go-xxh/go.sum"
go -C "$out/go-xxh" build -mod=mod -o "$out/go-xxh/run" .
python3 - "$out" <<'PY'
import json, os, pathlib, statistics, subprocess, sys, time
work=pathlib.Path(sys.argv[1])
runner=(work/'runner').read_text().strip()
commands={
 'go-direct':[str(work/'go-xxh/run')],
 'go-via-letgo':[os.environ['LG'],'checks/fixtures/compute/xxh-go.lg'],
 'llvm-aot':[str(work/'xxh')],
 'llvm-orc':[runner,str(work/'xxh.bc')],
}
env=dict(os.environ,LW_ORC_CACHE_DIR=str(work/'cache'),LW_ORC_STATS='1')
results={name:[] for name in commands}
def run(name):
 start=time.perf_counter()
 p=subprocess.run(commands[name],env=env,capture_output=True,text=True,check=True)
 wall=time.perf_counter()-start
 checksum,ns=map(int,p.stdout.split())
 assert checksum == -8755576988160712384, (name,p.stdout)
 if name=='llvm-orc':assert 'hits=1 misses=0' in p.stderr,p.stderr
 return dict(compute_ns=ns,process_seconds=wall,checksum=checksum,stderr=p.stderr)
# Prewarm each executable; previous benchmark has already seeded ORC objects.
for name in commands:run(name)
# Rotate order each round rather than timing all samples of one engine together.
names=list(commands)
for i in range(7):
 for name in names[i%4:]+names[:i%4]:
  results[name].append(run(name))
(work/'go-comparison.json').write_text(json.dumps(results,indent=2)+'\n')
for name,samples in results.items():
 ms=[s['compute_ns']/1e6 for s in samples]
 print(name, 'mean_ms',statistics.mean(ms),'sd_ms',statistics.stdev(ms))
PY
