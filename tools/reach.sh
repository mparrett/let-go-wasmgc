#!/usr/bin/env bash
# tools/reach.sh [--deftests] [--extra <ns>=<file>]... [--exclude-ns <ns>]... <program-root> <ns-prefix> [ns...]
#   — refresh a reach list.
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
# xsofy.test.*) but not legmacs's (test/*, ns test.*: on the ns path, outside
# the legmacs prefix; root them with a second run, prefix test.).
#
# Reproduced the probe's lists (same entries, C-sorted) on 2026-10-01 (lg 4e769212):
#   tools/reach.sh $LW_ROOT/xsofy xsofy     > corpus/natives/natives-xsofy.txt    # 71 ns
#   tools/reach.sh $LW_ROOT/legmacs legmacs > corpus/natives/natives-legmacs.txt  # 29 ns
#   comm -12 corpus/natives/natives-{xsofy,legmacs}.txt > corpus/natives/natives-shared.txt
#
# --extra <ns>=<file> adds a namespace whose file is NOT where require looks
# (legmacs' main.lg holds legmacs.main at the root): the scratch dir gets the
# file linked at its ns path, and -source-paths is the scratch dir, which
# mirrors the root. --deftests also roots at every deftest body (reach.lg's
# def-heads omits deftest, so a test file otherwise contributes only its
# helper defns); it runs a copy of reach.lg with deftest added, made in the
# scratch dir. --exclude-ns drops a namespace from the default roots
# (legmacs' test.run calls (run-tests) at load, so requiring it runs them).
#
# The legmacs list since P6.7 (2026-10-02) also roots at main.lg and the
# tests (review4 bug-05: core/sleep is reached only from main.lg's job
# loop, core/promise only from the tests); the exact command is in the
# header of corpus/natives/natives-legmacs.txt.
#
# reach.lg resolves relative slurps (test fixtures) against its cwd and spits
# reach-natives.txt into it, so it runs in a scratch dir that mirrors the
# program root's top level with symlinks: the checkout is never written.
#
# Env: LG (native lg), LETGO (let-go checkout whose pkg/rt/core sources are
# indexed; should be at the SHA the lg was built from).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$0")/../checks/env.sh"
LETGO=${LETGO:-$LW_ROOT/let-go}
reach_lg=$here/../emit-wasm-probe/reach.lg

extras=() exclude_ns=() deftests=0
while [ $# -gt 0 ]; do
  case $1 in
    --deftests) deftests=1; shift ;;
    --extra) extras+=("${2:?--extra needs <ns>=<file>}"); shift 2 ;;
    --exclude-ns) exclude_ns+=("${2:?--exclude-ns needs a namespace}"); shift 2 ;;
    *) break ;;
  esac
done
root=$(cd "${1:?usage: tools/reach.sh [--extra ns=file]... [--exclude-ns ns]... <program-root> <ns-prefix> [ns...]}" && pwd)
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

# an --extra file is linked at its ns path; each directory on the way that is
# a symlink into the root becomes a real dir of links, so the checkout is
# never written
materialize() {  # <dir under $work>: make it a real directory of links
  local d=$1 tgt e
  if [ -L "$d" ]; then
    tgt=$(readlink "$d"); rm "$d"; mkdir "$d"
    for e in "$tgt"/* "$tgt"/.[!.]*; do
      if [ -e "$e" ]; then ln -s "$e" "$d/${e##*/}"; fi
    done
  elif [ ! -d "$d" ]; then
    mkdir "$d"
  fi
}
for x in ${extras[@]+"${extras[@]}"}; do
  xns=${x%%=*} xfile=$root/${x#*=}
  [ -f "$xfile" ] || { echo "--extra: no file $xfile" >&2; exit 2; }
  rel=$(printf '%s' "$xns" | tr '.-' '/_').lg
  d=$work
  IFS=/ read -r -a parts <<<"${rel%/*}"
  if [ "$rel" != "${rel%/*}" ]; then
    for part in "${parts[@]}"; do d=$d/$part; materialize "$d"; done
  fi
  rm -f "$work/$rel"; ln -s "$xfile" "$work/$rel"
done

# ns → file for every .lg under the program root
find "$root" -name '*.lg' -not -path '*/.git/*' -not -path '*/worktrees/*' -not -path '*/dist/*' \
  | while IFS= read -r f; do
      n=$(awk '/^\(ns /{print $2; exit}' "$f")
      # only files `require` can find: main.lg's xsofy.main lives at the root,
      # not at xsofy/main.lg, so it cannot be a root
      rel=$(printf '%s' "$n" | tr '.-' '/_').lg
      if [ -n "$n" ] && [ "$f" = "$root/$rel" ]; then printf '%s\t%s\n' "$n" "$f"; fi
    done > "$work/.ns-map.all"
for x in ${extras[@]+"${extras[@]}"}; do printf '%s\t%s\n' "${x%%=*}" "$root/${x#*=}" >> "$work/.ns-map.all"; done
LC_ALL=C sort "$work/.ns-map.all" > "$work/.ns-map"

if [ $# -eq 0 ]; then
  printf '%s\n' ${exclude_ns[@]+"${exclude_ns[@]}"} > "$work/.exclude"
  awk -F'\t' -v p="$prefix" 'NR==FNR {skip[$1]=1; next} index($1, p) == 1 && !($1 in skip) {print $1}' "$work/.exclude" "$work/.ns-map" > "$work/.nses"
else
  printf '%s\n' "$@" > "$work/.nses"
fi
[ -s "$work/.nses" ] || { echo "no namespaces to root at" >&2; exit 2; }

{ find "$LETGO/pkg/rt/core" -name '*.lg' | LC_ALL=C sort
  awk -F'\t' 'NR==FNR {want[$1]=1; next} ($1 in want) {print $2}' "$work/.nses" "$work/.ns-map"
} > "$work/.files"

missing=$(awk -F'\t' 'NR==FNR {have[$1]=1; next} !($1 in have)' "$work/.ns-map" "$work/.nses")
[ -z "$missing" ] || { echo "no source file for: $missing" >&2; exit 2; }

if [ "$deftests" = 1 ]; then
  sed 's/^(def def-heads (quote #{def /(def def-heads (quote #{deftest def /; s/^(def def-heads '"'"'#{def /(def def-heads '"'"'#{deftest def /' "$reach_lg" > "$work/.reach.lg"
  grep -q 'deftest def ' "$work/.reach.lg" || { echo "--deftests: reach.lg's def-heads line changed; update the sed" >&2; exit 2; }
  reach_lg=$work/.reach.lg
fi
(cd "$work" && xargs "$LG" -source-paths "$work" "$reach_lg" .files "$prefix" < .nses) >&2
LC_ALL=C sort "$work/reach-natives.txt"
