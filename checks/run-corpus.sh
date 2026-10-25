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
#
# Limits (checks/limit.sh). Each run of a program, native or backend, gets
# 5 s of CPU and 30 s on the clock. Each compile gets 300 s on the clock
# (LW_COMPILE_LIMIT), a hang guard rather than a speed bar: dense files
# compile in 15 s on a quiet machine and passed 60 s at a load average of 8.
# A *_test.lg is cumulative: 5 s per deftest, at most 120 s.
# checks/run-corpus.timeout grants exceptions, one line per program:
# `<path from the repo root> <cpu-s> [<compile-s>]  # reason`. The clock limit
# of a run is twice its CPU limit, at least 30 s. A runner that does not use
# limit.sh is still stopped by a cap on the whole program. A program over a
# limit prints TIMEOUT and fails. A dir whose runs add up to more than 120 s
# (LW_SUITE_LIMIT) prints SLOW-SUITE and fails. LW_RUN_TIMES=<file> appends
# `<program> <step> <wall-s> <cpu-s> <cpu limit>` per step, for setting grants.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$0")/env.sh"
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

files=() fdirs=()
for d in "${dirs[@]}"; do
  [ -d "$d" ] || { echo "no such dir: $d" >&2; exit 2; }
  # A SKIP file in the dir lists basenames to leave out (empty since D230; `#` starts a comment).
  skip=""; [ -f "$d/SKIP" ] && skip=$(sed -e 's/#.*//' "$d/SKIP" | tr '\n' ' ')
  while IFS= read -r f; do
    case " $skip " in *" $(basename "$f") "*) echo "SKIP            $f"; continue;; esac
    files+=("$f"); fdirs+=("$d")
  done < <(find "$d" -maxdepth 1 -type f \( -name '*.lg' -o -name '*.clj' \) | LC_ALL=C sort)
done
[ ${#files[@]} -gt 0 ] || { echo "no programs in: ${dirs[*]}" >&2; exit 2; }

if [ $update -eq 1 ]; then
  for f in "${files[@]}"; do
    case $f in */opmatrix/*) ;; *) [ -e "$f.expected" ] || continue ;; esac
    "$LG" ${LG_ARGS:-} "$f" >"$f.expected" 2>/dev/null || echo "warn: native lg exited $? on $f" >&2
    echo "wrote $f.expected"
  done
  exit 0
fi

runner=${WASM_RUN:-$root/checks/wasm-run.sh}
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
  # also at LW_PAR=1: a cold build inside the first program would hit its
  # compile limit
  [ -x "$runner" ] || return 0
  local d=${LW_RTLIB_DIR:-$root/src/.rtlib} newest w v
  # A custom runner warms its own target and owns its cache (2026-10-03).
  if [ "$runner" != "$root/checks/wasm-run.sh" ]; then
    "$root/checks/sem.sh" timeout -k 5 "${LW_WARM_LIMIT:-600}" "$runner" "$root/corpus/scalar/fib.clj" >/dev/null 2>&1
    return 0  # a failed warm-up shows again, with its message, in the first program
  fi
  # Only this run's eval variant counts (D231): the eval library is
  # rtlib-<target>-<hex key>..., the no-eval one rtlib-<target>-noeval-...
  if [ "${LW_NO_EVAL:-}" = 1 ]; then v=noeval-; else v='[0-9a-f]'; fi
  newest=$(ls -t "$d"/rtlib-${LW_TARGET:-gc}-$v*.edn 2>/dev/null | head -1)
  if [ -n "$newest" ] && [ -z "$(find "$root/src" "$root/rt/wasm" "$root/rt/let-go/lang" -name '*.lg' -newer "$newest" 2>/dev/null | head -1)" ]; then return 0; fi
  w=$(mktemp -d)
  # background + wait, so a TERM during the (long) build reaches the trap now, not after it
  "$root/checks/sem.sh" timeout -k 5 "${LW_WARM_LIMIT:-600}" "$LG" -source-paths "$root/src" "$root/src/driver.lg" "$root/corpus/scalar/fib.clj" "$w/m.wat" >/dev/null 2>&1 &
  wait $!
  rm -rf "$w"
}

# One program -> $t/<i>.line (its report line(s)) and $t/<i>.cls (match|hard|ni).
prog() {
  local i=$1 f=$2 out cls w ns n nrc brc o rc
  out=$t/$i.line; cls=$t/$i.cls; w=$t/$i.w
  if [ -e "$f.expected" ]; then
    # LG_ARGS as oracle.sh passes it (a multi-namespace program's -source-paths)
    "$root/checks/limit.sh" run "$LG" ${LG_ARGS:-} "$f" >"$w/native.out" 2>/dev/null
    if ! cmp -s "$f.expected" "$w/native.out"; then
      { echo "STALE-EXPECTED $f"; diff "$f.expected" "$w/native.out" | head -4 | sed 's/^/    /'; } >"$out"
      echo hard >"$cls"; return
    fi
  fi
  case $f in
    *_test.lg) if [ "$both" -eq 1 ]; then
      ns=$(sed -nE 's/^\(ns ([^ )]+).*/\1/p' "$f" | head -1)
      n=$(grep -c '^(deftest ' "$f")
      "$root/checks/limit.sh" run "$LG" -source-paths "$root/rt:$(dirname "$f")" "$root/checks/intrinsics-native-runner.lg" "$n" "$ns" >"$w/nat.out" 2>&1; nrc=$?
      "$root/checks/run-tests.sh" "$f" >"$w/bk.out" 2>&1; brc=$?
      if [ $nrc -eq 0 ] && [ $brc -eq 0 ]; then
        echo "MATCH $f ($(grep -m1 '^PASS' "$w/bk.out" | sed -E 's/^PASS [^ ]+ //'))" >"$out"; echo match >"$cls"
      else
        { echo "MISMATCH $f: native $([ $nrc -eq 0 ] && echo ok || grep -m1 'intrinsics-native' "$w/nat.out"), backend $([ $brc -eq 0 ] && echo ok || grep -m1 '^FAIL' "$w/bk.out" | sed -E 's/^FAIL [^ ]+ //')"
          grep -m1 '^    wasm' "$w/bk.out"; } >"$out"; echo hard >"$cls"
      fi
      return
    fi ;;
  esac
  if [ ! -x "$runner" ]; then
    echo "NOT IMPLEMENTED $f (checks/wasm-run.sh missing)" >"$out"; echo ni >"$cls"; return
  fi
  o=$(WASM_RUN=$runner "$root/checks/oracle.sh" "$f" 2>&1); rc=$?
  case $rc in
    0) echo "MATCH $f" >"$out"; echo match >"$cls" ;;
    3) echo "NOT IMPLEMENTED $f: $(printf '%s' "$o" | head -1)" >"$out"; echo ni >"$cls" ;;
    *) { echo "MISMATCH $f: $(printf '%s' "$o" | head -1)"
         printf '%s\n' "$o" | sed -n '2,6p' | sed 's/^/    /'; } >"$out"; echo hard >"$cls" ;;
  esac
}

# One program under its limits. Also $t/<i>.runs (its runs' seconds, for the
# suite cap); $t/<i>.done is written last, so a reader that sees it sees all.
one() {
  local i=$1 f=$2 w=$t/$1.w b rel cpu="" n wall comp="" cap rc why
  mkdir -p "$w"; : >"$w/limits"
  b=$(basename "$f")
  rel=$(cd "$(dirname "$f")" && pwd)/$b; rel=${rel#"$root"/}
  read -r cpu comp < <(sed -e 's/#.*//' "$root/checks/run-corpus.timeout" 2>/dev/null | awk -v f="$rel" '$1==f{print $2, $3; exit}')
  if [ -z "$cpu" ]; then
    cpu=5
    case $b in *_test.lg) n=$(grep -c '^(deftest ' "$f"); cpu=$((5 * (n > 0 ? n : 1))); [ $cpu -gt 120 ] && cpu=120 ;; esac
  fi
  wall=$((2 * cpu)); [ $wall -lt 30 ] && wall=30
  comp=${comp:-${LW_COMPILE_LIMIT:-300}}
  # the whole program: two runs, a compile, and room for the rest
  cap=$((comp + 2 * wall + 60))
  LW_LIMIT_RUN="$cpu $wall" LW_LIMIT_COMPILE=$comp LW_LIMIT_LOG=$w/limits \
    timeout -k 5 "$cap" bash -c 'prog "$1" "$2"' _ "$i" "$f"; rc=$?
  why=$(grep -m1 '^TIMEOUT' "$w/limits" | sed -E 's/^TIMEOUT ([a-z]+) ([a-z]+) (.*)$/\1, \2 \3/')
  [ -z "$why" ] && { [ $rc -eq 124 ] || [ $rc -eq 137 ]; } && why="whole program, wall ${cap}s"
  if [ -n "$why" ]; then
    echo "TIMEOUT $f ($why)" >"$t/$i.line"; echo hard >"$t/$i.cls"
  fi
  awk '$1=="run"{s+=$2} END{printf "%.2f\n", s}' "$w/limits" >"$t/$i.runs"
  [ -n "${LW_RUN_TIMES:-}" ] && awk -v f="$rel" -v c="$cpu" '$1!="TIMEOUT"{print f, $0, c}' "$w/limits" >>"$LW_RUN_TIMES"
  : >"$t/$i.done"
}
export -f prog one
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
    printf '%s\t%s\n' "${fdirs[$i]}" "$(cat "$t/$i.runs")" >>"$t/suites"
  else
    echo "MISSING-RESULT ${files[$i]}"; hard=1
  fi
}
if [ "$par" -eq 1 ]; then
  for ((i=0; i<${#files[@]}; i++)); do "$sem" bash -c 'one "$1" "$2" "$3"' _ "$i" "${files[$i]}" "${fdirs[$i]}" & wait $!; emit "$i"; done
else
  for ((i=0; i<${#files[@]}; i++)); do printf '%s\0%s\0%s\0' "$i" "${files[$i]}" "${fdirs[$i]}"; done \
    | xargs -0 -n 3 -P "$par" "$sem" bash -c 'one "$1" "$2" "$3"' _ &
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
# the suite cap: a dir's runs (not its compiles) add up to at most 120 s
slow=$(awk -F'\t' -v cap="${LW_SUITE_LIMIT:-120}" '{s[$1]+=$2; if (!($1 in o)) o[$1]=n++}
  END {for (d in s) if (s[d] > cap) printf "%d\tSLOW-SUITE %s (runs %.0f s, cap %s s)\n", o[d], d, s[d], cap}' "$t/suites" 2>/dev/null | sort -n | cut -f2-)
[ -n "$slow" ] && { echo "$slow"; hard=1; }
echo "$match/${#files[@]} MATCH"
[ $hard -eq 1 ] && exit 1
[ $match -eq ${#files[@]} ] && exit 0
# what is left is NOT IMPLEMENTED: not built yet
exit 3
