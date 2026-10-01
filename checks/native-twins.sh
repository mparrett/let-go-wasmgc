#!/usr/bin/env bash
# checks/native-twins.sh <reach-list> [--manifest FILE] [--exclude REGEX]  — the P2.8/P3.1 check.
#
# For a reach list (one `ns/name` per line, as tools/reach.sh writes), print
# every native with no wasm twin, grouped by ns, with the inventory's arity,
# source and registration columns, then `MISSING n / REACHED m`.
# Exit 0 iff n = 0; 1 otherwise; 2 when an input is missing.
#
# Twins come from the real manifest (`tools/twin-manifest.lg`: `:twin`
# metadata on rt/wasm defns). Until any marker exists it falls back to
# corpus/natives/manifest-proposed.tsv under a PROPOSED MANIFEST banner.
# --manifest FILE overrides both (TSV, twin in column 1; used to falsify).
# --exclude REGEX drops reach-list entries matching the (awk ERE) regex
# before scoring, e.g. --exclude 'term/' (D58: term/* is Phase 4); they are
# counted on an EXCLUDED line, never as reached.
#
# A twin covers every var bound to the same NativeFn (the inventory's
# same-fn-as column): a twin for core/trim covers string/trim.
#
# A bare file name that does not exist is looked up in corpus/natives/, so
# `corpus/natives-shared.txt` (the items.tsv spelling) resolves too.
#
# Env: LG (native lg; default = the plan's pinned main build),
#      RT (runtime sources scanned for markers; default rt/wasm).
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
inv=corpus/natives/inventory.tsv

reach=${1:?usage: checks/native-twins.sh <reach-list> [--manifest FILE] [--exclude REGEX]}
shift
manifest_override=
exclude=
while [ $# -gt 0 ]; do
  case $1 in
    --manifest) manifest_override=${2:?--manifest needs a file}; shift 2 ;;
    --exclude) exclude=${2:?--exclude needs a regex}; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ ! -f "$reach" ] && [ -f "corpus/natives/${reach##*/}" ]; then
  reach=corpus/natives/${reach##*/}
fi
[ -f "$reach" ] || { echo "no reach list: $reach" >&2; exit 2; }
[ -f "$inv" ] || { echo "no inventory: $inv (run tools/native-inventory.lg)" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "$manifest_override" ]; then
  [ -f "$manifest_override" ] || { echo "no manifest: $manifest_override" >&2; exit 2; }
  grep -v '^#' "$manifest_override" > "$tmp/manifest"
  echo "manifest: $manifest_override (override)"
else
  "$LG" tools/twin-manifest.lg "${RT:-rt/wasm}" > "$tmp/manifest" || { echo "tools/twin-manifest.lg failed" >&2; exit 2; }
  if [ -s "$tmp/manifest" ]; then
    echo "manifest: :twin markers in ${RT:-rt/wasm} ($(wc -l < "$tmp/manifest" | tr -d ' ') claims)"
  else
    grep -v '^#' corpus/natives/manifest-proposed.tsv > "$tmp/manifest"
    echo "################################################################"
    echo "# PROPOSED MANIFEST: no :twin markers in rt/wasm yet; using"
    echo "# corpus/natives/manifest-proposed.tsv (name-matched, every"
    echo "# confidence counted, low included). Not a claim by the runtime."
    echo "################################################################"
  fi
fi
echo "inventory: $(head -1 "$inv" | sed 's/^# native inventory: //')"
echo "reach list: $reach"
[ -n "$exclude" ] && echo "exclude: $exclude"

awk -F'\t' -v invf="$inv" -v manf="$tmp/manifest" -v ex="$exclude" '
  BEGIN {
    while ((getline l < invf) > 0) {
      if (l ~ /^#/) continue
      split(l, c, "\t")
      ar[c[1]] = c[2]; src[c[1]] = c[3]; via[c[1]] = c[4]
      grp[c[1]] = (c[6] != "" && c[6] != "-") ? c[6] : c[1]
    }
    while ((getline l < manf) > 0) {
      split(l, c, "\t")
      if (c[1] == "") continue
      g = (c[1] in grp) ? grp[c[1]] : c[1]
      claimed[g] = 1
      if (!(c[1] in grp)) bogus[c[1]] = 1
    }
    for (b in bogus) printf "WARN manifest claims %s, which is not a native in the inventory\n", b
  }
  /^[ \t]*$/ { next }
  ex != "" && $1 ~ ex { excluded++; next }
  {
    q = $1; reached++
    g = (q in grp) ? grp[q] : q
    if (g in claimed) next
    i = index(q, "/"); ns = (i > 1) ? substr(q, 1, i - 1) : "?"
    if (!(q in grp)) ns = "NOT IN INVENTORY"
    line = sprintf("  %-36s %-8s %-40s %s", q, (q in ar) ? ar[q] : "?", (q in src) ? src[q] : "?", (q in via) ? via[q] : "?")
    rows[ns] = rows[ns] line "\n"; cnt[ns]++; missing++
  }
  END {
    n = 0
    for (ns in cnt) keys[++n] = ns
    # largest group first, then by name
    for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++)
      if (cnt[keys[j]] > cnt[keys[i]] || (cnt[keys[j]] == cnt[keys[i]] && keys[j] < keys[i])) { t = keys[i]; keys[i] = keys[j]; keys[j] = t }
    for (i = 1; i <= n; i++) { printf "== %s (%d)\n%s", keys[i], cnt[keys[i]], rows[keys[i]] }
    if (excluded > 0) printf "EXCLUDED %d (%s)\n", excluded, ex
    printf "MISSING %d / REACHED %d\n", missing + 0, reached + 0
    exit (missing > 0) ? 1 : 0
  }
' "$reach"
