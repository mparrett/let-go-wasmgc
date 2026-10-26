#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
LW_TARGET=llvm LW_RTLIB_DIR="$t/cache" "$LG" -source-paths src checks/llvm-rtlib-reuse-check.lg

# Optional integration: real lowering and executable behavior across two host
# profiles. Run the whole script under bench-baton when enabling this part.
if [ "${LLVM_RTLIB_REUSE_FULL:-0}" = 1 ]; then
  export LW_RTLIB_DIR="$t/real-cache" LLVM_REUSE_PROFILES="$t"
  "$LG" -source-paths src -e '(require (quote lower-llvm-profile)) (let [p (lower-llvm-profile/load-profile nil) d (os/getenv "LLVM_REUSE_PROFILES")] (spit (str d "/a.edn") (pr-str p)) (spit (str d "/b.edn") (pr-str (assoc p :fixnum-bits 31))))'
  p=corpus/scalar/fib.clj
  "$LG" "$p" > "$t/expected"
  LW_PROFILE="$t/a.edn" bash checks/native-run.sh "$p" > "$t/a.out"
  cmp "$t/expected" "$t/a.out"
  python3 - "$LW_RTLIB_DIR" "$t/a-files.json" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = {p.name: p.stat().st_mtime_ns for p in root.iterdir()}
assert any(n.endswith('.edn') for n in files), 'A did not publish a runtime snapshot'
pathlib.Path(sys.argv[2]).write_text(json.dumps(files))
PY
  LW_PROFILE="$t/b.edn" bash checks/native-run.sh "$p" > "$t/b.out"
  cmp "$t/expected" "$t/b.out"
  LW_PROFILE="$t/a.edn" bash checks/native-run.sh "$p" > "$t/a-again.out"
  cmp "$t/expected" "$t/a-again.out"
  python3 - "$LW_RTLIB_DIR" "$t/a-files.json" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
original = json.loads(pathlib.Path(sys.argv[2]).read_text())
current = {p.name: p.stat().st_mtime_ns for p in root.iterdir()}
assert len(current) > len(original), 'B did not publish a distinct profile entry'
assert all(current.get(n) == stamp for n, stamp in original.items()), 'A was removed or rebuilt'
print('PASS real profile A/B/A: native output matches, original A snapshot reused')
PY
fi
