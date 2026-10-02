#!/usr/bin/env bash
# checks/native-twins.sh <reach-list> [--manifest FILE] [--exclude REGEX] [--skip FILE]
#   — the P2.8/P3.1/P6.0 check.
#
# For a reach list (one `ns/name` per line, as tools/reach.sh writes; `#`
# lines are comments, e.g. the regeneration command in the header), print
# every native with no wasm twin, grouped by ns, with the inventory's arity,
# source and registration columns, then `MISSING n / REACHED m`.
# Exit 0 iff n = 0; 1 otherwise; 2 when an input is missing or the --skip
# file has an error.
#
# Twins come from the real manifest (`tools/twin-manifest.lg`: `:twin`
# metadata on rt/wasm defns, plus the backend's routing tables in src/:
# lw_rt's ext-twins/extra-twins and lower_wasm's value-substs). Until any marker exists it falls back to
# corpus/natives/manifest-proposed.tsv under a PROPOSED MANIFEST banner.
# --manifest FILE overrides both (TSV, twin in column 1; used to falsify).
# --exclude REGEX drops reach-list entries matching the (awk ERE) regex
# before scoring, e.g. --exclude 'term/' (D58: term/* is Phase 4); they are
# counted on an EXCLUDED line, never as reached.
#
# --skip FILE names natives that are out of the current phase by decision:
# one `<native> <reason>` per line (`#` comments and blank lines ignored).
# A reached native without a twin that the file names is listed on a
# SKIPPED line with its reason and not counted as missing. The file cannot
# rot: an entry that is not in the reach list (after --exclude), that has a
# twin, that is listed twice, or that has no reason is a SKIP ERROR, and
# any SKIP ERROR makes the exit 2 whatever the missing count.
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

reach=${1:?usage: checks/native-twins.sh <reach-list> [--manifest FILE] [--exclude REGEX] [--skip FILE]}
shift
manifest_override=
exclude=
skip=
while [ $# -gt 0 ]; do
  case $1 in
    --manifest) manifest_override=${2:?--manifest needs a file}; shift 2 ;;
    --exclude) exclude=${2:?--exclude needs a regex}; shift 2 ;;
    --skip) skip=${2:?--skip needs a file}; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ ! -f "$reach" ] && [ -f "corpus/natives/${reach##*/}" ]; then
  reach=corpus/natives/${reach##*/}
fi
[ -f "$reach" ] || { echo "no reach list: $reach" >&2; exit 2; }
if [ -n "$skip" ] && [ ! -f "$skip" ] && [ -f "corpus/natives/${skip##*/}" ]; then
  skip=corpus/natives/${skip##*/}
fi
[ -z "$skip" ] || [ -f "$skip" ] || { echo "no skip file: $skip" >&2; exit 2; }
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
    nroute=$(awk -F'\t' '$3 ~ /(^|\/)src\/[a-z_]+\.lg:[a-z-]+$/' "$tmp/manifest" | wc -l | tr -d ' ')
    echo "manifest: :twin markers in ${RT:-rt/wasm} ($(( $(wc -l < "$tmp/manifest") - nroute )) claims) + backend routes in src/ ($nroute claims)"
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
[ -n "$skip" ] && echo "skip: $skip"
: > "$tmp/skip"
[ -n "$skip" ] && grep -v '^[[:space:]]*#' "$skip" | grep -v '^[[:space:]]*$' > "$tmp/skip"

awk -F'\t' -v invf="$inv" -v manf="$tmp/manifest" -v ex="$exclude" -v skipf="$tmp/skip" '
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
    nskip = 0
    while ((getline l < skipf) > 0) {
      sub(/^[ \t]+/, "", l)
      q = l; sub(/[ \t].*$/, "", q)
      r = substr(l, length(q) + 1); sub(/^[ \t]+/, "", r); sub(/[ \t]+$/, "", r)
      if (q in skipwhy) { skiperr[++nerr] = sprintf("%s is listed twice", q); continue }
      if (r == "") { skiperr[++nerr] = sprintf("%s has no reason", q) }
      skipwhy[q] = r; skiporder[++nskip] = q
    }
  }
  /^[ \t]*$/ { next }
  /^[ \t]*#/ { next }
  ex != "" && $1 ~ ex { excluded++; next }
  {
    q = $1; reached++; inreach[q] = 1
    g = (q in grp) ? grp[q] : q
    if (g in claimed) { if (q in skipwhy) skiperr[++nerr] = sprintf("%s has a twin; drop it from the skip file", q); next }
    if (q in skipwhy) { skipped++; next }
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
    for (i = 1; i <= nskip; i++) {
      q = skiporder[i]
      if (!(q in inreach)) skiperr[++nerr] = sprintf("%s is not in the reach list%s", q, ex != "" ? " (after --exclude)" : "")
    }
    if (skipped > 0) {
      printf "== SKIPPED (%d)\n", skipped
      for (i = 1; i <= nskip; i++) { q = skiporder[i]; g = (q in grp) ? grp[q] : q; if ((q in inreach) && !(g in claimed)) printf "  %-36s %s\n", q, skipwhy[q] }
    }
    for (i = 1; i <= nerr; i++) printf "SKIP ERROR %s\n", skiperr[i]
    if (excluded > 0) printf "EXCLUDED %d (%s)\n", excluded, ex
    if (skipped > 0) printf "SKIPPED %d\n", skipped
    printf "MISSING %d / REACHED %d\n", missing + 0, reached + 0
    if (nerr > 0) exit 2
    exit (missing > 0) ? 1 : 0
  }
' "$reach"
