#!/usr/bin/env bash
# checks/emit-linked.sh [program...] — row P10.2: stage 3b-i of
# docs/SELF-HOST-SPEC.md (D193). A module compiles forms at run time and
# runs them against its own runtime: compiled = eval = native.
#
# The compiler host, corpus/emit/host/host.lg, is built once with
# LW_EXPORT_RT=1 LW_RUNTIME_COMPILE=1 (cached under $LW_EMIT_HOST_DIR, default
# $TMPDIR/lw-emit-host, by a hash of src/, rt/ and the host program; its own
# rtlib dir there, so the default src/.rtlib is not rebuilt). Then for each
# program of corpus/scalar/, corpus/opmatrix/*.lg, corpus/typed/*.lg and
# corpus/emit/*.lg (or the ones named), host/node-host.mjs --forms runs it
# twice in that host:
#   compile  each top-level form through "lw compile", linked and run (a
#            top-level try: its body compiled as a thunk, the try evaluated
#            around a call of it; node-host.mjs's header)
#   eval     each top-level form through "lw eval" (wasm.eval/eval)
# and each leg goes through checks/oracle.sh (stdout, exit class, first error
# line) against native lg. A program is SKIPped, with the reason, when its
# directory's SKIP file lists it, when the compile leg stops at a wasm.emit
# named limit (node-host exit 4), or when a leg stops at the evaluator's own
# limit, shared by both legs (its core table lacks a name native resolves:
# "Can't resolve"; a core value with no runtime twin, D139; or a
# "lower-wasm: ... (named limit)") where native's run says no such thing.
# A leg whose disagreement was traced (by asking native) to a component
# outside the compiled path is reported, not failed: the evaluator's
# declared arity-text limit (eval.lg header), and corpus/emit/KNOWN's rows
# (`program leg reason`). Prints MATCH/MISMATCH/SKIP per program, the skip
# list, the known list, "n/fit MATCH (total programs)" and the wall time. Exit 0 iff every fitting program MATCHes on
# both legs; 2 if node or wasm-tools is missing. Env: LG (env.sh),
# LW_EMIT_TIMEOUT (seconds per leg, default 900).
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/checks/env.sh"

# oracle.sh's WASM_RUN: replay a leg's recorded run
if [ "${1:-}" = --replay ]; then
  d=$2
  cat "$d/out"; cat "$d/err" >&2; exit "$(cat "$d/x")"
fi

command -v node >/dev/null || { echo "node not on PATH"; exit 2; }
command -v wasm-tools >/dev/null || { echo "wasm-tools not on PATH"; exit 2; }
cd "$root"
t0=$(date +%s)
t=$(mktemp -d "${TMPDIR:-/tmp}/emit-linked.XXXXXX"); trap 'rm -rf "$t"' EXIT
limit=${LW_EMIT_TIMEOUT:-900}

key=$( { git ls-files -s src rt corpus/emit/host; git diff HEAD -- src rt corpus/emit/host; } | shasum | cut -c1-12)
hd=${LW_EMIT_HOST_DIR:-${TMPDIR:-/tmp}/lw-emit-host}/$key
host=$hd/host.wasm
if [ ! -f "$host" ]; then
  mkdir -p "$hd"
  s=$(date +%s)
  LW_EXPORT_RT=1 LW_RUNTIME_COMPILE=1 LW_RTLIB_DIR="$hd/rtlib" \
    "$LG" -source-paths "$root/src" "$root/src/driver.lg" corpus/emit/host/host.lg "$hd/host.wat" >"$hd/build.log" 2>&1 \
    || { echo "host build failed:"; tail -20 "$hd/build.log"; exit 1; }
  wasm-tools parse "$hd/host.wat" -o "$hd/host.wasm.tmp" && wasm-tools validate "$hd/host.wasm.tmp" \
    || { echo "host module invalid"; exit 1; }
  mv "$hd/host.wasm.tmp" "$host"
  echo "host built in $(( $(date +%s) - s ))s: $(wc -c < "$host" | tr -d ' ') bytes ($key)"
fi

if [ $# -gt 0 ]; then progs=("$@"); else
  progs=()
  while IFS= read -r f; do progs+=("$f"); done < <(
    { find corpus/scalar -maxdepth 1 -type f \( -name '*.lg' -o -name '*.clj' \)
      find corpus/opmatrix corpus/typed corpus/emit -maxdepth 1 -type f -name '*.lg'; } | LC_ALL=C sort)
fi

listed() {
  local sf; sf=$(dirname "$1")/SKIP
  # a bare name skips the program in every check; "<row> name" in this row only
  [ -f "$sf" ] && awk -v b="$(basename "$1")" -v r=P10.2 '/^#/ {c=$0; next} $1==b || ($1==r && $2==b) {sub(/^# */, "", c); print c; found=1} END {exit !found}' "$sf"
}
first_err() { sed -E 's/\x1b\[[0-9;]*m//g' "$1/out" "$1/err" | grep -m1 -i 'error' ; }

n=${#progs[@]} fit=0 match=0 bad=0 skips=() knowns=()
for ((i=0; i<n; i++)); do
  f=${progs[$i]}
  if why=$(listed "$f"); then skips+=("$f: $(dirname "$f")/SKIP: $why"); echo "SKIP $f"; continue; fi
  "$LG" "$f" >"$t/native.txt" 2>&1
  for m in compile eval; do
    d=$t/$i/$m; mkdir -p "$d"
    timeout "$limit" node host/node-host.mjs "$host" --forms "$f" --mode "$m" >"$d/out" 2>"$d/err"; echo $? >"$d/x"
  done
  cx=$(cat "$t/$i/compile/x") ex=$(cat "$t/$i/eval/x")
  why=""
  if [ "$cx" = 4 ]; then why="named limit: $(first_err "$t/$i/compile" | sed 's/^error: //')"
  else
    for m in compile eval; do
      e=$(grep -h -m1 -o -E "Can't resolve [^ ]+ in this context|lower-wasm: [^ ]+ has no twin|lower-wasm: .*\(named limit\)" "$t/$i/$m/err" "$t/$i/$m/out" | head -1)
      # native's own run says the same: not the evaluator's limit
      if [ -n "$e" ] && ! grep -q -F "$e" "$t/native.txt"; then why="the evaluator's limit ($m leg): $e"; break; fi
    done
  fi
  if [ -n "$why" ]; then skips+=("$f: $why"); echo "SKIP $f"; continue; fi
  fit=$((fit+1)) res="" known=""
  for m in compile eval; do
    x=$(cat "$t/$i/$m/x")
    if [ "$x" = 124 ]; then res="$res $m: timeout after ${limit}s;"; continue; fi
    if o=$(WASM_RUN="$root/checks/emit-linked.sh --replay $t/$i/$m" checks/oracle.sh "$f" 2>&1); then continue; fi
    e=$(first_err "$t/$i/$m")
    if [ "$m" = eval ] && printf '%s' "$e" | grep -q -E 'function <fn> expected|function <mfn > doesn'"'"'t have'; then
      known="$known eval: the evaluator's arity text (eval.lg's named limit);"
    elif k=$(awk -v p="$f" -v l="$m" '$1==p && $2==l {$1=$2=""; sub(/^ +/, ""); print; f=1} END {exit !f}' corpus/emit/KNOWN 2>/dev/null); then
      known="$known $m: $k;"
    else res="$res $m: $(printf '%s' "$o" | head -1);"; fi
  done
  if [ -n "$res" ]; then bad=1; echo "MISMATCH $f:$res"
    for m in compile eval; do [ "$(cat "$t/$i/$m/x")" = 0 ] || echo "    $m: $(first_err "$t/$i/$m")"; done
  elif [ -n "$known" ]; then match=$((match+1)); knowns+=("$f:$known"); echo "MATCH $f (known:$known)"
  else match=$((match+1)); echo "MATCH $f"; fi
done
echo "skipped (${#skips[@]}):"
for s in "${skips[@]+"${skips[@]}"}"; do echo "  $s"; done
echo "known disagreements outside the compiled path (${#knowns[@]}):"
for s in "${knowns[@]+"${knowns[@]}"}"; do echo "  $s"; done
echo "$match/$fit MATCH ($n programs, ${#skips[@]} skipped)"
echo "emit-linked: wall $(( $(date +%s) - t0 ))s"
[ $bad = 0 ]
