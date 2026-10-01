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
# A program may instead carry
#   ;; refuse-runtime: <text>
# (P1.7) when the refusal can only happen at run time (whether a printed
# value is a fn is not known statically): the driver must then COMPILE it,
# and steps 2 and 3 apply unchanged. A program carrying both headers is
# NO-HEADER (ambiguous).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
dir=${1:?usage: refuse.sh <dir>}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
n=0; ok=0
for f in $(find "$dir" -maxdepth 1 -type f \( -name '*.lg' -o -name '*.clj' \) | LC_ALL=C sort); do
  n=$((n+1))
  want=$(sed -n 's/^;; refuse: //p' "$f" | head -1)
  wantrt=$(sed -n 's/^;; refuse-runtime: //p' "$f" | head -1)
  if [ -n "$want" ] && [ -n "$wantrt" ]; then echo "NO-HEADER    $f (both refuse: and refuse-runtime:)"; continue; fi
  if [ -z "$want" ] && [ -z "$wantrt" ]; then echo "NO-HEADER    $f"; continue; fi
  if [ -n "$want" ]; then
    if "$LG" -source-paths "$here/src" "$here/src/driver.lg" "$f" "$t/m.wat" >/dev/null 2>&1; then
      echo "ACCEPTED     $f (the driver compiled it; want: $want)"; continue
    fi
  else
    want=$wantrt
    if ! "$LG" -source-paths "$here/src" "$here/src/driver.lg" "$f" "$t/m.wat" >/dev/null 2>&1; then
      echo "COMPILE-FAIL $f (want a run-time refusal: $want)"; continue
    fi
  fi
  "$here/checks/wasm-run.sh" "$f" >"$t/out" 2>&1; x=$?
  if [ $x -eq 0 ]; then echo "ACCEPTED     $f (wasm-run exited 0)"; continue; fi
  first=$(sed -E 's/\x1b\[[0-9;]*m//g' "$t/out" | grep -m1 '^error:' | sed 's/^error: //')
  case "$first" in
    "lower-wasm: $want"*) echo "REFUSED      $f: $first"; ok=$((ok+1)) ;;
    *) echo "WRONG-ERROR  $f: want 'lower-wasm: $want', got '$first'" ;;
  esac
done
echo "$ok/$n refused as documented"
[ $n -gt 0 ] && [ $ok -eq $n ]
