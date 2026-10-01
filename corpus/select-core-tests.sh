#!/usr/bin/env bash
# Select let-go test/*_test.lg files that exercise only the Phase 2 runtime
# surface (core collections, seqs, strings, arithmetic). A file is IN unless
# it mentions anything from the EXCLUDE list: host I/O, reflection, regex,
# concurrency, deftype/protocols, dynamic binding, read-string, interop.
# Deterministic: the committed core-tests.txt is this script's output at the
# let-go SHA named in its first line; rerun and diff when let-go moves.
#   corpus/select-core-tests.sh [let-go-dir] > corpus/core-tests.txt
set -euo pipefail
LETGO=${1:-$HOME/projects-new/3p/let-go}
EXCLUDE='os/|io/|http|\(eval|in-ns|intern|resolve|ns-publics|re-find|re-matches|re-pattern|re-seq|\(format|future|\(go |thread|deftype|defprotocol|defrecord|reify|defmulti|with-redefs|slurp|spit|System/|async|Thread|\(\. |import|java\.|gogen|ir\.|lower|\*ns\*|read-string|load-string|term/|js/|binding|set!|alter-var-root|bigint|ratio|\(double|float|Math/'
echo "# let-go $(git -C "$LETGO" rev-parse --short HEAD) $(date +%F); file<TAB>deftests"
cd "$LETGO/test"
for f in *_test.lg; do
  if ! rg -q "$EXCLUDE" "$f" </dev/null; then printf '%s\t%s\n' "$f" "$(rg -c '\(deftest' "$f" </dev/null || echo 0)"; fi
done
