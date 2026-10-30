#!/usr/bin/env bash
# checks/refuse.sh <dir> — P1.4. Every program in <dir> carries a header line
#   ;; refuse: <text>
# naming the error the backend must refuse it with. For each program:
#   1. the driver alone (the compile step of wasm-run.sh) must fail, so the
#      refusal is at compile time, not a run-time throw;
#   2. checks/wasm-run.sh must exit non-zero;
#   3. the first `error:` line of its output must read `lower-wasm: <text>`.
# Prints one line per program (REFUSED / ACCEPTED / WRONG-ERROR / NO-HEADER)
# and exits 0 iff every program was refused as documented.
#
# corpus/refused holds two (as of 2026-10-02): dot-interop (:dot), infn-def
# (:def in a fn). P1.4's fourth, the variadic `& args` defn, compiles since
# P2.12 (D83) and moved to corpus/closure/variadic.lg; set-var (:set-var)
# compiles since P6.1 and moved to corpus/wasm/dynvars/set-var.lg.
#
# A program may instead carry
#   ;; refuse-runtime: <text>
# (P1.7) when the refusal can only happen at run time (whether a printed
# value is a fn is not known statically): the driver must then COMPILE it,
# and steps 2 and 3 apply unchanged. A program carrying both headers is
# NO-HEADER (ambiguous).
#
# LW_LANE=llvm runs the same programs on the llvm lane (checks/native-run.sh,
# `--target llvm`, the `llvm: ` prefix). A program may carry its twin there:
#   ;; refuse-llvm: <text>   the llvm lane refuses it with this text instead
#   ;; refuse-llvm: none     the llvm lane compiles it, and it must MATCH
#                            native lg (checks/oracle.sh)
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$0")/env.sh"
dir=${1:?usage: refuse.sh <dir>}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# LW_LANE=llvm checks the llvm lane: its runner and driver flags, its error
# prefix, and each program's `;; refuse-llvm:` twin when it has one
lane=${LW_LANE:-gc}
case $lane in
  gc) run=$here/checks/wasm-run.sh dflags= prefix="lower-wasm: " ;;
  llvm) run=$here/checks/native-run.sh dflags="--target llvm" prefix="llvm: " ;;
  *) echo "LW_LANE must be gc or llvm (got '$lane')" >&2; exit 2 ;;
esac
n=0; ok=0
for f in $(find "$dir" -maxdepth 1 -type f \( -name '*.lg' -o -name '*.clj' \) | LC_ALL=C sort); do
  n=$((n+1))
  want=$(sed -n 's/^;; refuse: //p' "$f" | head -1)
  wantrt=$(sed -n 's/^;; refuse-runtime: //p' "$f" | head -1)
  if [ "$lane" = llvm ]; then
    # the llvm lane's twin: its own refusal text, or none (it compiles the
    # program, which must then behave as native lg's)
    tw=$(sed -n 's/^;; refuse-llvm: //p' "$f" | head -1)
    if [ "$tw" = none ]; then
      o=$(WASM_RUN="$run" "$here/checks/oracle.sh" "$f" 2>&1 | tail -1)
      case "$o" in MATCH*) echo "MATCH        $f (llvm compiles it)"; ok=$((ok+1)) ;; *) echo "MISMATCH     $f: $o" ;; esac
      continue
    fi
    [ -n "$tw" ] && { want=$tw; wantrt=; }
  fi
  if [ -n "$want" ] && [ -n "$wantrt" ]; then echo "NO-HEADER    $f (both refuse: and refuse-runtime:)"; continue; fi
  if [ -z "$want" ] && [ -z "$wantrt" ]; then echo "NO-HEADER    $f"; continue; fi
  if [ -n "$want" ]; then
    if "$LG" -source-paths "$here/src" "$here/src/driver.lg" $dflags "$f" "$t/m.out" >/dev/null 2>&1; then
      echo "ACCEPTED     $f (the driver compiled it; want: $want)"; continue
    fi
  else
    want=$wantrt
    if ! "$LG" -source-paths "$here/src" "$here/src/driver.lg" $dflags "$f" "$t/m.out" >/dev/null 2>&1; then
      echo "COMPILE-FAIL $f (want a run-time refusal: $want)"; continue
    fi
  fi
  "$run" "$f" >"$t/out" 2>&1; x=$?
  if [ $x -eq 0 ]; then echo "ACCEPTED     $f ($(basename "$run") exited 0)"; continue; fi
  first=$(sed -E 's/\x1b\[[0-9;]*m//g' "$t/out" | grep -m1 '^error:' | sed 's/^error: //')
  # a run-time refusal the runtime raises itself (a named limit, such as the
  # GC lane's protocols) has no backend prefix; a compile-time one always does
  case "$first" in
    "$prefix$want"*) echo "REFUSED      $f: $first"; ok=$((ok+1)) ;;
    "$want"*) if [ -n "$wantrt" ]; then echo "REFUSED      $f: $first"; ok=$((ok+1)); else echo "WRONG-ERROR  $f: want '$prefix$want', got '$first'"; fi ;;
    *) echo "WRONG-ERROR  $f: want '$prefix$want', got '$first'" ;;
  esac
done
echo "$ok/$n refused as documented"
[ $n -gt 0 ] && [ $ok -eq $n ]
