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
#   --both             accepted and ignored for now; P2.1 will use it to also
#                      run each program under native lg with the reference impl.
#
# Env: LG (native lg; default = the plan's pinned main build).
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
export LG
update=0
dirs=()
for a in "$@"; do
  case $a in
    --both) ;;
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
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
match=0 hard=0 ni=0
for f in "${files[@]}"; do
  if [ -e "$f.expected" ]; then
    "$LG" "$f" >"$t/native.out" 2>/dev/null
    if ! cmp -s "$f.expected" "$t/native.out"; then
      echo "STALE-EXPECTED $f"
      diff "$f.expected" "$t/native.out" | head -4 | sed 's/^/    /'
      hard=1; continue
    fi
  fi
  if [ ! -x "$runner" ]; then
    echo "NOT IMPLEMENTED $f (checks/wasm-run.sh missing)"; ni=1; continue
  fi
  out=$(WASM_RUN=$runner "$root/checks/oracle.sh" "$f" 2>&1); rc=$?
  case $rc in
    0) echo "MATCH $f"; match=$((match+1)) ;;
    2) echo "NOT IMPLEMENTED $f: $(printf '%s' "$out" | head -1)"; ni=1 ;;
    *) echo "MISMATCH $f: $(printf '%s' "$out" | head -1)"
       printf '%s\n' "$out" | sed -n '2,6p' | sed 's/^/    /'; hard=1 ;;
  esac
done
echo "$match/${#files[@]} MATCH"
[ $hard -eq 1 ] && exit 1
[ $match -eq ${#files[@]} ] && exit 0
exit 2
