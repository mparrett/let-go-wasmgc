#!/usr/bin/env bash
# tools/reach.sh <program-root> <ns-prefix> [ns...]  — refresh a reach list.
#
# Thin wrapper over ../emit-wasm-probe/reach.lg (called in place): which Go
# natives does a program reach transitively? Roots are every def in the named
# namespaces; lg-defined core fns are followed through let-go's sources; Go
# natives are the leaves. Prints the sorted `ns/name` list on stdout (the
# format checks/native-twins.sh reads) and reach.lg's summary on stderr.
#
# With no ns arguments, every ns under <program-root> whose file is where
# `require` looks for it (<root>/<ns-path>.lg) and whose name starts with
# <ns-prefix> is a root. That includes xsofy's tests (xsofy/test/*, ns
# xsofy.test.*) and excludes legmacs's (test/*, off the ns path).
#
# Reproduced the probe's lists (same entries, C-sorted) on 2026-10-01 (lg 4e769212):
#   tools/reach.sh ~/projects-new/3p/xsofy xsofy     > corpus/natives/natives-xsofy.txt    # 71 ns
#   tools/reach.sh ~/projects-new/3p/legmacs legmacs > corpus/natives/natives-legmacs.txt  # 29 ns
#   comm -12 corpus/natives/natives-{xsofy,legmacs}.txt > corpus/natives/natives-shared.txt
#
# reach.lg resolves relative slurps (test fixtures) against its cwd and spits
# reach-natives.txt into it, so it runs in a scratch dir that mirrors the
# program root's top level with symlinks: the checkout is never written.
#
# Env: LG (native lg), LETGO (let-go checkout whose pkg/rt/core sources are
# indexed; should be at the SHA the lg was built from).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
LETGO=${LETGO:-$HOME/projects-new/3p/let-go}
reach_lg=$here/../emit-wasm-probe/reach.lg

root=$(cd "${1:?usage: tools/reach.sh <program-root> <ns-prefix> [ns...]}" && pwd)
prefix=${2:?ns-prefix required}
shift 2

lg_sha=$("$LG" -version 2>/dev/null | sed -n 's/.*(\([0-9a-f]\{7,\}\)).*/\1/p' | head -1)
if [ -n "$lg_sha" ] && ! git -C "$LETGO" merge-base --is-ancestor "$lg_sha" HEAD 2>/dev/null; then
  echo "warning: $LETGO HEAD is not at or after lg's $lg_sha; core sources may not match the binary" >&2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for e in "$root"/* "$root"/.[!.]*; do
  if [ -e "$e" ]; then ln -s "$e" "$work/${e##*/}"; fi
done

# ns → file for every .lg under the program root
find "$root" -name '*.lg' -not -path '*/.git/*' -not -path '*/worktrees/*' -not -path '*/dist/*' \
  | while IFS= read -r f; do
      n=$(awk '/^\(ns /{print $2; exit}' "$f")
      # only files `require` can find: main.lg's xsofy.main lives at the root,
      # not at xsofy/main.lg, so it cannot be a root
      rel=$(printf '%s' "$n" | tr '.-' '/_').lg
      if [ -n "$n" ] && [ "$f" = "$root/$rel" ]; then printf '%s\t%s\n' "$n" "$f"; fi
    done | LC_ALL=C sort > "$work/.ns-map"

if [ $# -eq 0 ]; then
  awk -F'\t' -v p="$prefix" 'index($1, p) == 1 {print $1}' "$work/.ns-map" > "$work/.nses"
else
  printf '%s\n' "$@" > "$work/.nses"
fi
[ -s "$work/.nses" ] || { echo "no namespaces to root at" >&2; exit 2; }

{ find "$LETGO/pkg/rt/core" -name '*.lg' | LC_ALL=C sort
  awk -F'\t' 'NR==FNR {want[$1]=1; next} ($1 in want) {print $2}' "$work/.nses" "$work/.ns-map"
} > "$work/.files"

missing=$(awk -F'\t' 'NR==FNR {have[$1]=1; next} !($1 in have)' "$work/.ns-map" "$work/.nses")
[ -z "$missing" ] || { echo "no source file for: $missing" >&2; exit 2; }

(cd "$work" && xargs "$LG" -source-paths "$root" "$reach_lg" .files "$prefix" < .nses) >&2
LC_ALL=C sort "$work/reach-natives.txt"
