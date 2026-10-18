#!/usr/bin/env bash
# checks/corpus-lint.sh [--lower | --commit-msg FILE] — hold the corpus to its
# budget (corpus/README.md).
#
# checks/corpus-budget.tsv: one row per top-level corpus directory with its
# base (tracked files, KB), the date the base was set, and the topics it serves.
# Its `# topics:` line is the topic vocabulary, which is also the set of
# git-issue labels `corpus:<topic>`. A directory's ceiling is its base plus an
# allowance (FILES_PER files, KB_PER KB) for each issue labelled with one of its
# topics, or a topic below one (a `lang` row counts `corpus:lang/fns`), where
# the label was added on or after the base date (new or existing issues alike).
# An untagged child (git-issue parent_of) takes its nearest tagged ancestor's
# topics, counted from the later of that label's date and its own creation. So the corpus grows where issues are filed, and a
# clone without the issue notes sees the base alone (stricter, never looser).
# The review*/ rows have no topics: closed, they only shrink.
# Labels may go below a topic for clarity (`corpus:lang/types/protocols` counts
# for `lang/types`). Fails on: a directory over its ceiling, a directory with no
# row, a directory outside review*/ without a README.md, a `corpus:` label
# outside the vocabulary, and a file outside review*/ named for one bug or probe (bug-*, probe-*, pNN-*); a fix adds a case to the file that
# owns the behavior.
#   --lower           after deleting, bring each base down to the current size.
#   --commit-msg FILE the commit-msg hook: a commit that adds a row, raises a
#                     base or changes topics cites the issue that justifies it,
#                     with an Issue:, Refs:, Fixes: or Closes: #<id> trailer.
# Reads git's index, so it checks what is about to be committed.
# CORPUS_LINT_NOTES overrides the issue ref pattern (tests).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
budget=checks/corpus-budget.tsv
FILES_PER=2 KB_PER=16
notes=${CORPUS_LINT_NOTES:-refs/notes/issue-*}

if [ "${1:-}" = --commit-msg ]; then
  # the '# HEAD' line keeps NR == FNR true only in the first input when HEAD has no budget
  raised=$(awk -F'\t' 'NR == FNR {if ($0 ~ /^# topics:/) v = $0; else if ($0 !~ /^#/) {n[$1] = $2; kb[$1] = $3; t[$1] = $5}; next}
    /^# topics:/ {if ($0 != v) print "  the topic vocabulary"; next} /^#/ {next}
    !($1 in n) || $2 > n[$1] || $3 > kb[$1] || $5 != t[$1] {print "  " $1}' \
    <(echo '# HEAD'; git show HEAD:"$budget" 2>/dev/null) <(git show :"$budget"))
  [ -z "$raised" ] && exit 0
  grep -qiE '^(Issue|Refs|Fixes|Closes): *#[0-9a-f]+' "${2:?--commit-msg FILE}" && exit 0
  echo "corpus-lint: this commit grows the corpus budget; cite the issue that justifies it (Issue: #<id> trailer):" >&2
  echo "$raised" >&2
  exit 1
fi

now=$(git ls-files --format='%(objectname) %(path)' corpus |
  git cat-file --batch-check="%(objectsize)	%(rest)" |
  awk -F'\t' '{split($2, p, "/"); d = (p[3] == "") ? "(top)" : p[2]; n[d]++; kb[d] += $1}
              END {for (d in n) printf "%s\t%d\t%d\n", d, n[d], (kb[d] + 1023) / 1024}' | sort)

if [ "${1:-}" = --lower ]; then
  awk -F'\t' 'BEGIN {OFS = "\t"} NR == FNR {n[$1] = $2; kb[$1] = $3; next}
    /^#/ || !($1 in n) {print; next}
    {if (n[$1] < $2) $2 = n[$1]; if (kb[$1] < $3) $3 = kb[$1]; print}' \
    <(printf '%s\n' "$now") "$budget" > "$budget.tmp" && mv "$budget.tmp" "$budget"
  exit 0
fi

# per issue: id, created date, children (parent_of), its corpus: topics now
issues=$(git for-each-ref --format='%(refname):issue %(refname)' "$notes" |
  git cat-file --batch='#OBJ %(objecttype) %(rest)' 2>/dev/null |
  awk 'function flush() {if (id != "") printf "%s\t%s\t%s\t%s\t%s\n", id, cr, (kids == "" ? "-" : kids), (tp == "" ? "-" : tp), ref; id = cr = kids = tp = ""}
       /^#OBJ blob / {flush(); ref = $3; next}
       /^#OBJ / || / missing$/ {flush(); next}
       /^id: / && id == "" {id = $2}
       /^created: / {cr = substr($2, 1, 10)}
       /^parent_of: / {kids = substr($0, 12); gsub(/[ #]/, "", kids)}
       /^labels: / {m = split(substr($0, 9), l, ","); for (i = 1; i <= m; i++) {gsub(/ /, "", l[i]); if (l[i] ~ /^corpus:/) tp = tp (tp == "" ? "" : " ") substr(l[i], 8)}}
       END {flush()}')
# the date each topic was added: the first note commit whose issue text lists it,
# so tagging an existing issue counts; one "<id> <date>:<topic>,..." line per tagged issue
dated=$(printf '%s\n' "$issues" | awk -F'\t' '$4 != "-" {print $5 "\t" $1 "\t" $4}' | while IFS=$'\t' read -r ref id tp; do
  git log -p --reverse --format='#DATE %cs' "$ref" -- issue | awk -v id="$id" -v cur="$tp" '
    BEGIN {n = split(cur, c, " "); for (i = 1; i <= n; i++) want[c[i]] = 1}
    /^#DATE / {d = $2; next}
    /^\+labels: / {m = split(substr($0, 10), l, ","); for (i = 1; i <= m; i++) {gsub(/ /, "", l[i]); t = substr(l[i], 8)
      if (l[i] ~ /^corpus:/ && (t in want) && !(t in seen)) {seen[t] = 1; out = out (out == "" ? "" : ",") d ":" t}}}
    END {print id "\t" out}'
done)
# one line per issue and topic: <date> <topic>. An untagged child takes its nearest
# tagged ancestor's topics, from the later of the label's date and its own creation.
labels=$(awk -F'\t' 'FNR == 1 {f++}
  f == 1 && NF >= 4 {cr[$1] = $2; ids[++m] = $1; if ($3 != "-") {n = split($3, k, ","); for (i = 1; i <= n; i++) par[k[i]] = $1}; next}
  f == 2 && NF == 2 {tg[$1] = $2}
  END {for (j = 1; j <= m; j++) {x = ids[j]; y = x; h = 0
         while (!(y in tg) && (y in par) && h < 64) {y = par[y]; h++}
         if (!(y in tg)) continue
         n = split(tg[y], a, ","); for (i = 1; i <= n; i++) {split(a[i], p, ":"); d = p[1]; if (y != x && cr[x] > d) d = cr[x]; print d, p[2]}}}' \
  <(printf '%s\n' "$issues") <(printf '%s\n' "$dated"))

# inputs in order: the budget, the labels, the current sizes
fail=$(awk -F'\t' -v FP=$FILES_PER -v KP=$KB_PER '
  FNR == 1 {f++}
  f == 2 {if (NF) {split($0, a, " "); ld[++nl] = a[1]; lt[nl] = a[2]}; next}
  f == 1 && /^# topics:/ {nv = split(substr($0, 11), v, " "); for (i = 1; i <= nv; i++) voc[v[i]] = 1; next}
  f == 1 {if ($0 !~ /^#/) {n[$1] = $2; kb[$1] = $3; d[$1] = $4; t[$1] = $5}; next}
  !($1 in n) {print "  corpus/" $1 ": no row in checks/corpus-budget.tsv (" $2 " files, " $3 " KB)"; next}
  {m = 0; nt = split(t[$1], ts, ",")
   for (j = 1; j <= nl; j++) {
     if (ld[j] < d[$1]) continue
     for (i = 1; i <= nt; i++) if (ts[i] != "-" && (lt[j] == ts[i] || index(lt[j], ts[i] "/") == 1)) {m++; break}}
   cf = n[$1] + m * FP; ck = kb[$1] + m * KP
   if ($2 > cf || $3 > ck) print "  corpus/" $1 ": " $2 " files, " $3 " KB over the ceiling of " cf " files, " ck " KB (base " n[$1] " files, " kb[$1] " KB + " m " issue(s) since " d[$1] ")"}
  END {for (j = 1; j <= nl; j++) {ok = 0; for (x in voc) if (lt[j] == x || index(lt[j], x "/") == 1) ok = 1
         if (!ok && !(lt[j] in seen)) {seen[lt[j]] = 1; print "  label corpus:" lt[j] ": not a topic, or below one, in checks/corpus-budget.tsv"}}}' \
  "$budget" <(printf '%s\n' "$labels") <(printf '%s\n' "$now"))
# every directory outside review*/ says what its topic covers
readme=$(git ls-files corpus | awk -F/ 'NF > 2 && $2 !~ /^review[0-9]*$/ {d[$2] = 1} NF == 3 && $3 == "README.md" {r[$2] = 1}
  END {for (x in d) if (!(x in r)) print "  corpus/" x ": no README.md (a summary of what the topic covers)"}' | sort)
named=$(git ls-files corpus | grep -vE '^corpus/review[0-9]*/' |
  awk -F/ '$NF ~ /^(bug|probe|p[0-9]+)[-_]/ {print "  " $0 ": named for one bug or probe; add the case to the file that owns the behavior"}')
[ -z "$fail$readme$named" ] && { echo "corpus-lint: within budget"; exit 0; }
echo "corpus-lint: see corpus/README.md (growth comes from issues labelled corpus:<topic>)" >&2
printf '%s\n' "$fail" "$readme" "$named" | grep . >&2
exit 1
