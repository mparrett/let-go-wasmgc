#!/usr/bin/env bash
# checks/run-corpus.sh [--both] [--update-expected] <dir>...
#
# For every *.lg / *.clj in the given dirs, run
#   WASM_RUN=checks/wasm-run.sh checks/oracle.sh <file>
# and print one line per file: MATCH, MISMATCH, NOT IMPLEMENTED, or
# STALE-EXPECTED. Then "n/total MATCH".
#
# oracle.sh is the match relation (it reruns native lg itself). A <file>.expected
# next to a program is a committed snapshot of native lg's stdout: it is checked
# first, and a difference is STALE-EXPECTED (counts as a failure), so a hand-edit
# or an lg that changed behaviour under the corpus is caught even before any
# backend exists. Files without .expected skip that step.
#
# Exit: 0 all MATCH; 1 any MISMATCH or STALE-EXPECTED; 2 otherwise not all
# MATCH because the backend (checks/wasm-run.sh) is missing or unimplemented.
#
#   --update-expected  rewrite every .expected from native lg and exit
#                      (programs that already have one, plus all of opmatrix/).
#   --both             P2.1: a *_test.lg file (deftests) MATCHes only when it
#                      passes (a) under native lg with the reference intrinsics
#                      (checks/intrinsics-native-runner.lg, deftest-count
#                      guard) AND (b) through the backend (checks/run-tests.sh:
#                      same summary and FAIL/ERROR lines as native run-tests).
#                      Other programs still go through oracle.sh.
#
# Env: LG (native lg; default = the plan's pinned main build).
#      LW_PAR  programs run at once (default 3; LW_PAR=1 = serial, in order).
#              Output is byte-identical at every value: each program's report
#              is captured to its own file and printed in sorted order (as
#              soon as it and all earlier ones are done), and the summary line
#              and exit code are computed from the same per-program results.
#              Each program holds one machine-wide slot (checks/sem.sh,
#              LW_SLOTS, default 4) so concurrent runs by several agents queue
#              instead of oversubscribing the machine.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
export LG
update=0 both=0
dirs=()
for a in "$@"; do
  case $a in
    --both) both=1 ;;
    --update-expected) update=1 ;;
    -*) echo "unknown flag $a" >&2; exit 2 ;;
    *) dirs+=("$a") ;;
  esac
done
[ ${#dirs[@]} -gt 0 ] || { echo "usage: $0 [--both] [--update-expected] <dir>..." >&2; exit 2; }

files=()
for d in "${dirs[@]}"; do
  [ -d "$d" ] || { echo "no such dir: $d" >&2; exit 2; }
  # A SKIP file in the dir lists basenames to leave out (D15: div-* until Phase 2).
  skip=""; [ -f "$d/SKIP" ] && skip=$(grep -v '^#' "$d/SKIP" | tr '\n' ' ')
  while IFS= read -r f; do
    case " $skip " in *" $(basename "$f") "*) echo "SKIP            $f"; continue;; esac
    files+=("$f")
  done < <(find "$d" -maxdepth 1 -type f \( -name '*.lg' -o -name '*.clj' \) | LC_ALL=C sort)
done
[ ${#files[@]} -gt 0 ] || { echo "no programs in: ${dirs[*]}" >&2; exit 2; }

if [ $update -eq 1 ]; then
  for f in "${files[@]}"; do
    case $f in */opmatrix/*) ;; *) [ -e "$f.expected" ] || continue ;; esac
    "$LG" "$f" >"$f.expected" 2>/dev/null || echo "warn: native lg exited $? on $f" >&2
    echo "wrote $f.expected"
  done
  exit 0
fi

runner=$root/checks/wasm-run.sh
par=${LW_PAR:-3}
case $par in ''|*[!0-9]*|0) echo "LW_PAR must be a positive integer (got '$par')" >&2; exit 2;; esac
t=$(mktemp -d)
export t root both
xp=""
# stop a whole subtree (xargs -> sem.sh -> worker -> lg), parent first so xargs
# starts no replacement, so an interrupted run
# leaves no workers or held slots behind
killtree() { local c kids; kids=$(pgrep -P "$1" 2>/dev/null); kill "$1" 2>/dev/null; for c in $kids; do killtree "$c"; done; return 0; }
trap 'for c in $(pgrep -P $$ 2>/dev/null); do killtree "$c"; done; rm -rf "$t"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM HUP

# The rtlib (src/.rtlib, or $LW_RTLIB_DIR) is built by the first driver run
# after a source change (45-175 s); N workers starting together would each
# build it (3 concurrent builds took 175 s against 45 s for one, identical
# output). So build it once, serially, before fanning out. A newer-than test
# on the cache file avoids an 8 s warm compile when nothing changed; a wrong
# guess costs only that compile or a redundant build, never a wrong result.
rtlib_warm() {
  [ "$par" -gt 1 ] && [ -x "$runner" ] || return 0
  local d=${LW_RTLIB_DIR:-$root/src/.rtlib} newest w
  newest=$(ls -t "$d"/rtlib-*.edn 2>/dev/null | head -1)
  if [ -n "$newest" ] && [ -z "$(find "$root/src" "$root/rt/wasm" -name '*.lg' -newer "$newest" 2>/dev/null | head -1)" ]; then return 0; fi
  w=$(mktemp -d)
  # background + wait, so a TERM during the (long) build reaches the trap now, not after it
  "$root/checks/sem.sh" "$LG" -source-paths "$root/src" "$root/src/driver.lg" "$root/corpus/scalar/fib.clj" "$w/m.wat" >/dev/null 2>&1 &
  wait $!
  rm -rf "$w"
}

# One program -> $t/<i>.line (its report line(s)) and $t/<i>.cls (match|hard|ni);
# $t/<i>.done is written last, so a reader that sees it sees both.
one() {
  local i=$1 f=$2 out cls w ns n nrc brc o rc
  out=$t/$i.line; cls=$t/$i.cls; w=$t/$i.w; mkdir -p "$w"
  if [ -e "$f.expected" ]; then
    "$LG" "$f" >"$w/native.out" 2>/dev/null
    if ! cmp -s "$f.expected" "$w/native.out"; then
      { echo "STALE-EXPECTED $f"; diff "$f.expected" "$w/native.out" | head -4 | sed 's/^/    /'; } >"$out"
      echo hard >"$cls"; : >"$t/$i.done"; return
    fi
  fi
  case $f in
    *_test.lg) if [ "$both" -eq 1 ]; then
      ns=$(sed -nE 's/^\(ns ([^ )]+).*/\1/p' "$f" | head -1)
      n=$(grep -c '^(deftest ' "$f")
      "$LG" -source-paths "$root/rt:$(dirname "$f")" "$root/checks/intrinsics-native-runner.lg" "$n" "$ns" >"$w/nat.out" 2>&1; nrc=$?
      "$root/checks/run-tests.sh" "$f" >"$w/bk.out" 2>&1; brc=$?
      if [ $nrc -eq 0 ] && [ $brc -eq 0 ]; then
        echo "MATCH $f ($(grep -m1 '^PASS' "$w/bk.out" | sed -E 's/^PASS [^ ]+ //'))" >"$out"; echo match >"$cls"
      else
        { echo "MISMATCH $f: native $([ $nrc -eq 0 ] && echo ok || grep -m1 'intrinsics-native' "$w/nat.out"), backend $([ $brc -eq 0 ] && echo ok || grep -m1 '^FAIL' "$w/bk.out" | sed -E 's/^FAIL [^ ]+ //')"
          grep -m1 '^    wasm' "$w/bk.out"; } >"$out"; echo hard >"$cls"
      fi
      : >"$t/$i.done"; return
    fi ;;
  esac
  if [ ! -x "$runner" ]; then
    echo "NOT IMPLEMENTED $f (checks/wasm-run.sh missing)" >"$out"; echo ni >"$cls"; : >"$t/$i.done"; return
  fi
  o=$(WASM_RUN=$runner "$root/checks/oracle.sh" "$f" 2>&1); rc=$?
  case $rc in
    0) echo "MATCH $f" >"$out"; echo match >"$cls" ;;
    2) echo "NOT IMPLEMENTED $f: $(printf '%s' "$o" | head -1)" >"$out"; echo ni >"$cls" ;;
    *) { echo "MISMATCH $f: $(printf '%s' "$o" | head -1)"
         printf '%s\n' "$o" | sed -n '2,6p' | sed 's/^/    /'; } >"$out"; echo hard >"$cls" ;;
  esac
  : >"$t/$i.done"
}
export -f one
export runner

rtlib_warm
sem=$root/checks/sem.sh
match=0 hard=0 ni=0
# Print program i's captured report and fold its class into the summary.
emit() {
  local i=$1
  if [ -e "$t/$i.done" ]; then
    cat "$t/$i.line"
    case $(cat "$t/$i.cls") in match) match=$((match+1));; hard) hard=1;; ni) ni=1;; esac
  else
    echo "MISSING-RESULT ${files[$i]}"; hard=1
  fi
}
if [ "$par" -eq 1 ]; then
  for ((i=0; i<${#files[@]}; i++)); do "$sem" bash -c 'one "$1" "$2"' _ "$i" "${files[$i]}" & wait $!; emit "$i"; done
else
  for ((i=0; i<${#files[@]}; i++)); do printf '%s\0%s\0' "$i" "${files[$i]}"; done \
    | xargs -0 -n 2 -P "$par" "$sem" bash -c 'one "$1" "$2"' _ &
  xp=$!
  # in sorted order, as soon as each program and all before it are done
  for ((i=0; i<${#files[@]}; i++)); do
    while [ ! -e "$t/$i.done" ]; do
      kill -0 "$xp" 2>/dev/null || break
      sleep 0.2
    done
    emit "$i"
  done
  wait "$xp" 2>/dev/null; xp=""
fi
echo "$match/${#files[@]} MATCH"
[ $hard -eq 1 ] && exit 1
[ $match -eq ${#files[@]} ] && exit 0
exit 2
