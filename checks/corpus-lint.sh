#!/usr/bin/env bash
# checks/corpus-lint.sh [--settle | --commit-msg FILE] — hold the corpus to its
# budget (corpus/README.md).
#
# checks/corpus-budget.tsv: one row per top-level corpus directory with its
# base (tracked files, KB) and the topics it serves. Its `# topics:` line is the
# topic vocabulary, which is also the set of git-issue labels `corpus:<topic>`.
# A directory's ceiling is its base plus an allowance (FILES_PER files, KB_PER
# KB) for each live issue (open, in_progress, review or blocked) labelled with
# one of its topics or a topic below one (a `lang` row counts
# `corpus:lang/fns`). An issue labelled `corpus-budget:<files>/<KB>` grants
# that instead, for work that needs more than a fix's case (a library test,
# its fixtures and a re-freeze under one issue). An untagged child (git-issue parent_of) takes its nearest
# tagged ancestor's topics. Closing or deferring an issue takes its room away:
# `--settle` then makes what was actually added the base. A clone without the
# issue notes sees the bases alone (stricter, never looser). The review*/ rows
# have no topics: closed, they only shrink.
# Fails on: a directory over its ceiling, a directory with no row, a directory
# outside review*/ without a README.md, a `corpus:` label outside the
# vocabulary, a malformed `corpus-budget:` label or one on an issue with no
# topic, and a file outside review*/ named for one bug or probe (bug-*,
# probe-*, pNN-*); a fix adds a case to the file that owns the behavior.
#   --settle          after an issue closes, or after deleting: each base becomes
#                     the directory's current size, as long as that is within
#                     the ceiling counting every tagged issue, live or not;
#                     commit it citing the closed issue (Refs: #<id>).
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
  raised=$(awk -F'\t' 'NR == FNR {if ($0 ~ /^# topics:/) v = $0; else if ($0 !~ /^#/) {n[$1] = $2; kb[$1] = $3; t[$1] = $4}; next}
    /^# topics:/ {if ($0 != v) print "  the topic vocabulary"; next} /^#/ {next}
    !($1 in n) || $2 > n[$1] || $3 > kb[$1] || $4 != t[$1] {print "  " $1}' \
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

# per issue: id, status, children (parent_of), its corpus: topics, its
# corpus-budget: override (or -)
issues=$(git for-each-ref --format='%(refname):issue' "$notes" | git cat-file --batch 2>/dev/null |
  awk 'function flush() {if (id != "") printf "%s\t%s\t%s\t%s\t%s\n", id, st, (kids == "" ? "-" : kids), (tp == "" ? "-" : tp), (ov == "" ? "-" : ov); id = st = kids = tp = ov = ""}
       /^[0-9a-f]+ [a-z]+ [0-9]+$/ || / missing$/ {flush(); next}
       /^id: / && id == "" {id = $2}
       /^status: / {st = $2}
       /^parent_of: / {kids = substr($0, 12); gsub(/[ #]/, "", kids)}
       /^labels: / {m = split(substr($0, 9), l, ","); for (i = 1; i <= m; i++) {gsub(/ /, "", l[i]); if (l[i] ~ /^corpus:/) tp = tp (tp == "" ? "" : " ") substr(l[i], 8); else if (l[i] ~ /^corpus-budget:/) ov = substr(l[i], 15)}}
       END {flush()}')
# one line per issue and topic: <live|done> <topic> <files> <KB>; an untagged
# child takes its nearest tagged ancestor's topics, and is live or done, and
# sized, by its own status and corpus-budget: label
labels=$(printf '%s\n' "$issues" | awk -F'\t' -v FP=$FILES_PER -v KP=$KB_PER 'NF == 5 {st[$1] = $2; ov[$1] = $5; ids[++m] = $1; if ($4 != "-") tg[$1] = $4
    if ($3 != "-") {n = split($3, k, ","); for (i = 1; i <= n; i++) par[k[i]] = $1}}
  END {for (j = 1; j <= m; j++) {x = ids[j]; y = x; h = 0
         while (!(y in tg) && (y in par) && h < 64) {y = par[y]; h++}
         if (!(y in tg)) {if (ov[x] != "-") print "untopiced", x; continue}
         f = FP; kb = KP
         if (ov[x] != "-") {if (ov[x] !~ /^[0-9]+\/[0-9]+$/) {print "bad", x, ov[x]; continue}; split(ov[x], o, "/"); f = o[1]; kb = o[2]}
         live = (st[x] == "open" || st[x] == "in_progress" || st[x] == "review" || st[x] == "blocked") ? "live" : "done"
         n = split(tg[y], a, " "); for (i = 1; i <= n; i++) print live, a[i], f, kb}}')

# inputs in order: the budget, the labels, the current sizes. Prints, per row,
# "row <dir> <files> <KB> <ceiling files> <KB>" with every tagged issue counted
# (what --settle may absorb), and "fail <message>" lines.
report=$(awk -F'\t' '
  FNR == 1 {f++}
  f == 2 && /^untopiced / {split($0, a, " "); print "fail\t  issue #" a[2] ": a corpus-budget: label with no corpus:<topic> label, own or inherited, grants nothing (git issue update --labels replaces the whole list)"; next}
  f == 2 && /^bad / {split($0, a, " "); print "fail\t  issue #" a[2] ": corpus-budget:" a[3] " is not <files>/<KB>"; next}
  f == 2 {if (NF) {split($0, a, " "); ll[++nl] = a[1]; lt[nl] = a[2]; lf[nl] = a[3]; lk[nl] = a[4]}; next}
  f == 1 && /^# topics:/ {nv = split(substr($0, 11), v, " "); for (i = 1; i <= nv; i++) voc[v[i]] = 1; next}
  f == 1 {if ($0 !~ /^#/) {n[$1] = $2; kb[$1] = $3; t[$1] = $4}; next}
  !($1 in n) {print "fail\t  corpus/" $1 ": no row in checks/corpus-budget.tsv (" $2 " files, " $3 " KB)"; next}
  {live = lf_ = lk_ = af = ak = 0; nt = split(t[$1], ts, ",")
   for (j = 1; j <= nl; j++)
     for (i = 1; i <= nt; i++) if (ts[i] != "-" && (lt[j] == ts[i] || index(lt[j], ts[i] "/") == 1)) {
       af += lf[j]; ak += lk[j]; if (ll[j] == "live") {live++; lf_ += lf[j]; lk_ += lk[j]}; break}
   cf = n[$1] + lf_; ck = kb[$1] + lk_
   print "row\t" $1 "\t" $2 "\t" $3 "\t" (n[$1] + af) "\t" (kb[$1] + ak)
   if ($2 > cf || $3 > ck) print "fail\t  corpus/" $1 ": " $2 " files, " $3 " KB over the ceiling of " cf " files, " ck " KB (base " n[$1] " files, " kb[$1] " KB + " live " live issue(s); after an issue closes, --settle)"}
  END {for (j = 1; j <= nl; j++) {ok = 0; for (x in voc) if (lt[j] == x || index(lt[j], x "/") == 1) ok = 1
         if (!ok && !(lt[j] in seen)) {seen[lt[j]] = 1; print "fail\t  label corpus:" lt[j] ": not a topic, or below one, in checks/corpus-budget.tsv"}}}' \
  "$budget" <(printf '%s\n' "$labels") <(printf '%s\n' "$now"))

if [ "${1:-}" = --settle ]; then
  awk -F'\t' 'BEGIN {OFS = "\t"} NR == FNR {if ($1 == "row" && $3 <= $5 && $4 <= $6) {n[$2] = $3; kb[$2] = $4}; next}
    /^#/ || !($1 in n) {print; next} {$2 = n[$1]; $3 = kb[$1]; print}' \
    <(printf '%s\n' "$report") "$budget" > "$budget.tmp" && mv "$budget.tmp" "$budget"
  git diff --stat -- "$budget"
  exit 0
fi

fail=$(printf '%s\n' "$report" | awk -F'\t' '$1 == "fail" {print $2}')
# every directory outside review*/ says what its topic covers
readme=$(git ls-files corpus | awk -F/ 'NF > 2 && $2 !~ /^review[0-9]*$/ {d[$2] = 1} NF == 3 && $3 == "README.md" {r[$2] = 1}
  END {for (x in d) if (!(x in r)) print "  corpus/" x ": no README.md (a summary of what the topic covers)"}' | sort)
named=$(git ls-files corpus | grep -vE '^corpus/review[0-9]*/' |
  awk -F/ '$NF ~ /^(bug|probe|p[0-9]+)[-_]/ {print "  " $0 ": named for one bug or probe; add the case to the file that owns the behavior"}')
[ -z "$fail$readme$named" ] && { echo "corpus-lint: within budget"; exit 0; }
echo "corpus-lint: see corpus/README.md (room comes from live issues labelled corpus:<topic>)" >&2
printf '%s\n' "$fail" "$readme" "$named" | grep . >&2
exit 1
