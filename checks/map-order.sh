#!/usr/bin/env bash
# checks/map-order.sh [--native | --update]   — the P2.4 check.
#
# Default (the items.tsv row): both halves must pass.
#   1. checks/run-corpus.sh corpus/maporder — every map/set iteration-order
#      program MATCHes native lg under the backend (STALE-EXPECTED first).
#   2. let-go's test/map_order_test.lg under the backend via
#      checks/run-tests.sh. That runner does not exist yet: the half prints
#      NOT IMPLEMENTED and the check exits 2.
#   Exit: 0 both pass; 1 any MISMATCH / STALE-EXPECTED / test failure;
#   2 otherwise not done (backend or runner missing).
#
# --native  check the corpus itself, no backend: regenerate the programs into
#           a scratch dir with gen.lg and require them byte-identical to the
#           committed ones, then require native lg's stdout to equal every
#           .expected. Exit 0 clean, 1 on any drift. Writes nothing.
# --update  regenerate the programs in place and rewrite every .expected.
#
# Env: LG (native lg; default = the plan's pinned main build),
#      LETGO (let-go checkout holding test/map_order_test.lg).
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
LETGO=${LETGO:-$HOME/projects-new/3p/let-go}
export LG
dir=corpus/maporder

programs() { find "$dir" -maxdepth 1 -type f -name '*.lg' ! -name gen.lg | LC_ALL=C sort; }

case "${1:-}" in
  --update)
    "$LG" "$dir/gen.lg" "$dir/" || exit 1
    while IFS= read -r f; do
      "$LG" "$f" >"$f.expected" || { echo "native lg exited $? on $f" >&2; exit 1; }
    done < <(programs)
    echo "wrote $(programs | wc -l | tr -d ' ') .expected files"
    exit 0 ;;
  --native)
    t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
    bad=0
    "$LG" "$dir/gen.lg" "$t/" >/dev/null || { echo "FAIL gen.lg"; exit 1; }
    # generator drift: the committed programs must be exactly what gen.lg writes
    for g in "$t"/*.lg; do
      b=$(basename "$g")
      if ! cmp -s "$g" "$dir/$b"; then echo "STALE-PROGRAM $dir/$b"; bad=1; fi
    done
    n=0
    while IFS= read -r f; do
      n=$((n+1))
      [ -e "$t/$(basename "$f")" ] || { echo "ORPHAN-PROGRAM $f (gen.lg no longer writes it)"; bad=1; }
      if [ ! -e "$f.expected" ]; then echo "MISSING-EXPECTED $f"; bad=1; continue; fi
      "$LG" "$f" >"$t/out" 2>/dev/null
      if cmp -s "$f.expected" "$t/out"; then
        echo "OK $f ($(wc -l <"$f.expected" | tr -d ' ') lines)"
      else
        echo "STALE-EXPECTED $f"; diff "$f.expected" "$t/out" | head -4 | sed 's/^/    /'; bad=1
      fi
    done < <(programs)
    echo "$n programs checked natively"
    exit $bad ;;
  "") ;;
  *) echo "usage: $0 [--native | --update]" >&2; exit 2 ;;
esac

checks/run-corpus.sh "$dir"; corpus_rc=$?

test_file=$LETGO/test/map_order_test.lg
if [ -x checks/run-tests.sh ]; then
  checks/run-tests.sh "$test_file"; tests_rc=$?
else
  echo "NOT IMPLEMENTED $test_file (checks/run-tests.sh missing)"; tests_rc=2
fi

[ $corpus_rc -eq 1 ] || [ $tests_rc -eq 1 ] && exit 1
[ $corpus_rc -eq 0 ] && [ $tests_rc -eq 0 ] && exit 0
exit 2
