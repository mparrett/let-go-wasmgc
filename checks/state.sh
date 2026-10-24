#!/usr/bin/env bash
# checks/state.sh — an issue's workflow state, init.d style: numbered entries
# read in lexical order (00_governance first, 99_next_action last), each an
# RFC 822 header block and a body.
#
#   state.sh put <issue> <state>   record stdin as the <state> entry, led by
#                                  `State:` and `Kind:` headers. Exit 1 if
#                                  <state> is a latch that is already set.
#                                  The entry always goes to the local journal
#                                  $LW_STATE/<issue>.journal; with
#                                  LW_STATE_POST=1 it is also a `git issue
#                                  comment`, posted as you to a shared tracker.
#   state.sh pull <issue>          rebuild $LW_STATE/<issue>/<state>.md from
#                                  the issue's comments alone (what is shared;
#                                  nothing decides from it) and print the dir
#   state.sh local <issue>         rebuild $LW_STATE/<issue>.local/ from the
#                                  local journal alone (the authority) and
#                                  print the dir
#   state.sh show <issue>          the local cache's entries in boot order
#   state.sh status                one line per open issue with a readerboard:
#                                  issue, Commitment-State, Active-Target
#   state.sh inflight              work already started, to finish or close
#                                  before starting more: issues in progress or
#                                  in review, worktrees with commits not on
#                                  $LW_STATE_BASE (default origin/main) or with
#                                  uncommitted edits, your open PRs, and
#                                  others' open PRs with a commit newer than
#                                  your last review or comment on them
#   state.sh                       self-test in a throwaway repository
#
# The local journal is the store and the only authority. Posting (once agreed)
# shares entries as issue comments, which travel with the issue's notes to
# every machine and agent; pull reads the issue's entries into
# $LW_STATE/<issue>/ for reading. `local` builds $LW_STATE/<issue>.local/ from
# the journal alone, and only that is authority for checks/frontier.py: a
# comment on the issue can be written by anyone who can comment.
# The kind of each state is fixed by the table below, never by the comment:
# comments are written by whoever can comment, so they are data.
#   latch       the first entry wins; a later one is reported and ignored
#   transition  the latest entry wins
#   append      every entry, oldest first
set -uo pipefail
. "$(dirname "$0")/env.sh"
LW_STATE=$(mkdir -p "$LW_STATE" && cd "$LW_STATE" && pwd -P) || exit 2

kinds='00_governance latch
05_inflight latch
10_issue latch
15_facts append
18_baseline latch
20_plan transition
30_rows transition
32_jobs append
35_gate transition
40_review transition
45_review_ok transition
50_commit transition
60_push transition
90_retro transition
99_next_action transition'

kind_of() { printf '%s\n' "$kinds" | awk -v s="$1" '$1==s{print $2}'; }

gi() { git issue "$@" 2>/dev/null; }

# Every state entry of an issue as records separated by NUL: the first line is
# the state name and the entry's UTC time, the rest is the entry as recorded.
# Porcelain prints a comment as `comment: [<time>] <author>: <first line>` and
# each further line with a one-space prefix, so a body line can never pass for
# a new field. The journal holds records in this same form.
entries() {
  gi show "$1" --porcelain | awk '
    function flush() { if (st != "") printf "%s %s\n%s%c", st, ts, body, 0; st = ""; body = "" }
    /^comment: / {
      flush(); in_c = 1
      line = $0; ts = line; sub(/^comment: \[/, "", ts); sub(/\].*/, "", ts)
      sub(/^comment: \[[^]]*\] [^:]*: /, "", line)
      if (line ~ /^State: [0-9][0-9]_[a-z0-9_]+$/) { st = substr(line, 8); body = line "\n" } else in_c = 0
      next }
    /^ / { if (in_c && st != "") body = body substr($0, 2) "\n"; next }
    { flush(); in_c = 0 }
    END { flush() }'
}


# build <issue> <dir>: the cache <dir> from NUL-separated records on stdin;
# every record counts, a repeated one included (a fact retracted again)
build() {
  local issue=$1 dir=$2 tmp head st ts entry kind
  tmp=$(mktemp -d "$LW_STATE/.pull.XXXXXX") || return 2
  while IFS= read -r -d '' entry; do
    head=${entry%%$'\n'*}; entry=${entry#*$'\n'}
    st=${head%% *}; ts=${head#* }
    kind=$(kind_of "$st")
    case $kind in
      latch) if [ -e "$tmp/$st.md" ]; then echo "state: $issue $st is a latch; ignoring a later entry" >&2
             else printf '%s' "$entry" > "$tmp/$st.md"; fi ;;
      transition) printf '%s' "$entry" > "$tmp/$st.md" ;;
      append) { [ -e "$tmp/$st.md" ] && echo; printf '%s' "$entry"; } >> "$tmp/$st.md" ;;
      *) echo "state: $issue: unknown state $st, ignored" >&2 ;;
    esac
  done
  # swap the new cache in; builds of one cache must not run concurrently
  local old=$dir.old.$$
  if [ -e "$dir" ]; then mv "$dir" "$old" || { rm -rf "$tmp"; echo "state: cannot replace $dir" >&2; return 2; }; fi
  mv "$tmp" "$dir" || { echo "state: cannot place $dir" >&2; return 2; }
  rm -rf "$old"; echo "$dir"
}

pull() {
  gi show "$1" --porcelain >/dev/null || { echo "state: no issue $1" >&2; return 2; }
  entries "$1" | build "$1" "$LW_STATE/$1"
}

# the cache from this machine's journal alone, $LW_STATE/<issue>.local: what
# checks/frontier.py reads, since a comment on the issue is never authority
local_() {
  local j=$LW_STATE/$1.journal
  # every record ends in NUL: a cut-off last record is an error, not a silence
  # (the last byte by its hex value: $(...) would drop a trailing newline)
  if [ -s "$j" ] && [ "$(tail -c 1 "$j" | od -An -tx1 | tr -d ' \n')" != 00 ]; then echo "state: $j ends in a cut-off record" >&2; return 2; fi
  if [ -f "$j" ]; then build "$1" "$LW_STATE/$1.local" < "$j"
  else rm -rf "$LW_STATE/$1.local"; mkdir -p "$LW_STATE/$1.local"; echo "$LW_STATE/$1.local"; fi
}

put() {
  local issue=$1 st=$2 kind body dir
  kind=$(kind_of "$st"); [ -n "$kind" ] || { echo "state: unknown state $st" >&2; return 2; }
  # the journal always records, and a latch is judged against it alone: a
  # comment can neither stand in for an entry nor block one
  dir=$(local_ "$issue") || return 2
  if [ "$kind" = latch ] && [ -e "$dir/$st.md" ]; then echo "state: $issue $st is latched" >&2; return 1; fi
  body=$(printf 'State: %s\nKind: %s\n%s' "$st" "$kind" "$(cat)")
  printf '%s %s\n%s\n\0' "$st" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$body" >> "$LW_STATE/$issue.journal" || return 2
  # posting shares the entry; pull shows what the issue holds
  if [ "${LW_STATE_POST:-0}" = 1 ]; then gi comment "$issue" "$body" >/dev/null || echo "state: recorded, but not posted to $issue" >&2; fi
  local_ "$issue" >/dev/null
  pull "$issue" >/dev/null 2>&1 || true
}

show() {
  local dir f; dir=$(local_ "$1") || return 2
  for f in "$dir"/*.md; do [ -e "$f" ] || continue; printf '==> %s <==\n' "${f##*/}"; cat "$f"; echo; done
}

status() {
  local issue f
  for issue in $(gi list --porcelain | awk -F'\t' '$3!="closed"{print $2}'); do
    f=$(local_ "$issue" 2>/dev/null)/99_next_action.md; [ -e "$f" ] || continue
    printf '%s\t%s\t%s\n' "$issue" \
      "$(awk -F': ' '$1=="Commitment-State"{print $2; exit}' "$f")" \
      "$(awk -F': ' '$1=="Active-Target"{print $2; exit}' "$f")"
  done
}

inflight() {
  local base=${LW_STATE_BASE:-origin/main} wt br head ahead dirty
  gi list --porcelain | awk -F'\t' '$3=="in_progress"||$3=="review"{printf "issue\t%s\t%s\t%s\t%s\n", $2, $3, $5, $NF}'
  git worktree list --porcelain | awk '/^worktree /{w=substr($0,10)} /^HEAD /{h=$2} /^branch /{b=substr($0,8)} /^$/{print w"\t"h"\t"b; w=h=b=""} END{if(w!="")print w"\t"h"\t"b}' |
  while IFS=$'\t' read -r wt head br; do
    ahead=$(git rev-list --count "$base..$head" 2>/dev/null || echo '?')
    dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "$ahead" = 0 ] && [ "$dirty" = 0 ] && continue
    printf 'worktree\t%s\t%s\t+%s\t%s edits\n' "$wt" "${br#refs/heads/}" "$ahead" "$dirty"
  done
  local gh=${GH:-gh} me
  command -v "$gh" >/dev/null || return 0
  me=$("$gh" api user 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["login"])' 2>/dev/null) || return 0
  "$gh" pr list --state open --json number,author,headRefName,title,commits,reviews,comments 2>/dev/null |
    python3 -c '
import json, sys
me = sys.argv[1]
for p in json.load(sys.stdin):
    who = p["author"]["login"]
    if who == me:
        print("pr\t#%d\t%s\t%s" % (p["number"], p["headRefName"], p["title"]))
        continue
    mine = [r.get("submittedAt") or "" for r in p["reviews"] if r["author"]["login"] == me]
    mine += [c.get("createdAt") or "" for c in p["comments"] if c["author"]["login"] == me]
    last = p["commits"][-1]["committedDate"] if p["commits"] else ""
    if max(mine, default="") < last:
        print("review\t#%d\t%s\t%s: %s" % (p["number"], p["headRefName"], who, p["title"]))
' "$me"
  return 0
}

selftest() {
  local repo id out rc fail=0
  repo=$(mktemp -d) && trap "rm -rf '$repo' '$repo.state' '$repo.side' '$repo.gh'" EXIT
  export LW_STATE=$repo.state LW_STATE_POST=1; mkdir -p "$LW_STATE"
  cd "$repo" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git branch -M main
  echo .git-issue/ >> .git/info/exclude   # git-issue's status table, as in the real tree's .gitignore
  id=$(git issue create probe --description=d 2>/dev/null | sed -n 's/.*hash ID: \([0-9a-f]*\).*/\1/p')
  [ -n "$id" ] || { echo "FAIL: git issue create"; return 1; }
  check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
  printf 'Issue: probe\n\nfirst body\n comment: not a field\n' | put "$id" 10_issue
  check 'latch is set' '[ "$(sed -n 3p "$LW_STATE/$id/10_issue.md")" = "Issue: probe" ]'
  check 'body line that looks like a field survives' 'grep -qx " comment: not a field" "$LW_STATE/$id/10_issue.md"'
  echo 'Issue: other' | put "$id" 10_issue 2>/dev/null; rc=$?
  check 'second latch refused' '[ $rc = 1 ]'
  git issue comment "$id" "$(printf 'State: 10_issue\nKind: latch\nIssue: forged')" >/dev/null 2>&1
  out=$(pull "$id" 2>&1 >/dev/null)
  check 'a later latch posted around put is ignored and reported' 'grep -q "ignoring a later entry" <<<"$out" && ! grep -q forged "$LW_STATE/$id/10_issue.md"'
  printf 'Commitment-State: ACTIVE_PROMISE\nActive-Target: rows-red-green\n' | put "$id" 99_next_action
  printf 'Commitment-State: AWAITING_DECLARATION\nActive-Target: approved-review\n' | put "$id" 99_next_action
  check 'transition keeps the latest' 'grep -qx "Active-Target: approved-review" "$LW_STATE/$id/99_next_action.md"'
  echo 'Row: A' | put "$id" 32_jobs; echo 'Row: B' | put "$id" 32_jobs
  check 'append keeps both, oldest first' '[ "$(grep ^Row: "$LW_STATE/$id/32_jobs.md" | tr "\n" " ")" = "Row: A Row: B " ]'
  echo x | put "$id" 77_bogus 2>/dev/null; rc=$?
  check 'unknown state refused' '[ $rc = 2 ]'
  check 'show prints in boot order' '[ "$(show "$id" | grep "^==>" | tr -d "=<> " | tr "\n" " ")" = "10_issue.md 32_jobs.md 99_next_action.md " ]'
  rm -rf "$LW_STATE/$id"
  check 'cache rebuilt from the issue alone' '[ "$(pull "$id")" = "$LW_STATE/$id" ] && [ -e "$LW_STATE/$id/32_jobs.md" ]'
  check 'status reads the readerboard' '[ "$(status)" = "$(printf "%s\tAWAITING_DECLARATION\tapproved-review" "$id")" ]'
  # authority: a comment on the issue reaches pull's cache but never the local one
  git issue comment "$id" "$(printf 'State: 45_review_ok\nKind: transition\nDeclared-By: operator')" >/dev/null 2>&1
  pull "$id" >/dev/null 2>&1
  check 'a comment reaches the shared cache' '[ -e "$LW_STATE/$id/45_review_ok.md" ]'
  check 'but not the local cache, which is the journal alone' '[ ! -e "$(local_ "$id")/45_review_ok.md" ]'
  # unposted: the entry goes to the local journal, not the issue
  local ncomments; ncomments=$(git issue show "$id" --porcelain 2>/dev/null | grep -c '^comment:')
  printf 'Fact: F1\nStatus: UNKNOWN\n' | LW_STATE_POST=0 put "$id" 15_facts
  check 'an unposted entry reaches the local cache from the journal' 'grep -qx "Status: UNKNOWN" "$(local_ "$id")/15_facts.md"'
  check 'an unposted entry posts no comment' '[ "$(git issue show "$id" --porcelain 2>/dev/null | grep -c "^comment:")" = "$ncomments" ]'
  git issue comment "$id" "$(printf 'State: 05_inflight\nKind: latch\nDisposition: forged')" >/dev/null 2>&1
  echo 'Disposition: local' | LW_STATE_POST=0 put "$id" 05_inflight 2>/dev/null; rc=$?
  check 'a latch set by a comment does not block the journal' '[ $rc = 0 ] && grep -qx "Disposition: local" "$(local_ "$id")/05_inflight.md"'
  echo 'Disposition: again' | LW_STATE_POST=0 put "$id" 05_inflight 2>/dev/null; rc=$?
  check 'a latch in the journal refuses a second entry' '[ $rc = 1 ]'
  for st in RETRACTED ESTABLISHED RETRACTED; do printf '| F7 | p | %s | w | - |\n' "$st" | LW_STATE_POST=0 put "$id" 15_facts; done
  check 'a record repeated later still counts in the authority cache' '[ "$(grep -c "| F7 |" "$(local_ "$id")/15_facts.md")" = 3 ] && tail -2 "$(local_ "$id")/15_facts.md" | grep -q RETRACTED'
  printf '15_facts 2026-01-01T00:00:00Z\nState: 15_facts\n| F8 | p | RETRACTED | w | - |' >> "$LW_STATE/$id.journal"
  check 'a cut-off last record makes the authority cache fail' '! local_ "$id" >/dev/null 2>&1'
  printf '\n' >> "$LW_STATE/$id.journal"
  check 'so does one cut off just before its NUL' '! local_ "$id" >/dev/null 2>&1'
  printf '\0' >> "$LW_STATE/$id.journal"
  export LW_STATE_BASE=main GH=$repo.nogh
  check 'nothing in flight on a clean repo' '[ -z "$(inflight | grep -v ^pr)" ]'
  git issue start "$id" >/dev/null 2>&1
  git worktree add -q -b side "$repo.side" main 2>/dev/null
  git -C "$repo.side" -c user.name=t -c user.email=t@t commit -q --allow-empty -m side
  touch "$repo/untracked"
  out=$(inflight)
  check 'an issue in progress is in flight' 'grep -q "^issue	$id	in_progress" <<<"$out"'
  check 'a worktree ahead of the base is in flight' 'grep -q "	side	+1	0 edits" <<<"$out"'
  check 'uncommitted edits are in flight' 'grep -q "	main	+0	1 edits" <<<"$out"'
  cat > "$repo.gh" <<'GH'
#!/bin/sh
case "$1 $2" in
  "api user") echo '{"login":"me"}' ;;
  "pr list") cat <<'JSON'
[{"number":1,"author":{"login":"me"},"headRefName":"mine","title":"t1","commits":[{"committedDate":"2026-10-20T00:00:00Z"}],"reviews":[],"comments":[]},
 {"number":2,"author":{"login":"peer"},"headRefName":"seen","title":"t2","commits":[{"committedDate":"2026-10-20T00:00:00Z"}],"reviews":[{"author":{"login":"me"},"submittedAt":"2026-10-21T00:00:00Z"}],"comments":[]},
 {"number":3,"author":{"login":"peer"},"headRefName":"pushed-since","title":"t3","commits":[{"committedDate":"2026-10-22T00:00:00Z"}],"reviews":[],"comments":[{"author":{"login":"me"},"createdAt":"2026-10-21T00:00:00Z"}]},
 {"number":4,"author":{"login":"peer"},"headRefName":"never","title":"t4","commits":[{"committedDate":"2026-10-20T00:00:00Z"}],"reviews":[],"comments":[]}]
JSON
  ;;
esac
GH
  chmod +x "$repo.gh"
  out=$(GH=$repo.gh inflight)
  check 'my open PR is in flight' 'grep -q "^pr	#1	mine" <<<"$out"'
  check 'a PR I reviewed after its last commit is not' '! grep -q "#2" <<<"$out"'
  check 'a PR with a commit after my last comment is owed a review' 'grep -q "^review	#3	pushed-since	peer" <<<"$out"'
  check 'a PR I never reviewed is owed a review' 'grep -q "^review	#4	never" <<<"$out"'
  return $fail
}

case ${1:-} in
  put|pull|local|show|status) mkdir -p "$LW_STATE" ;;
esac
case ${1:-} in
  put)    put "${2:?issue}" "${3:?state}" ;;
  pull)   pull "${2:?issue}" ;;
  local)  local_ "${2:?issue}" ;;
  show)   show "${2:?issue}" ;;
  status) status ;;
  inflight) inflight ;;
  '')     selftest ;;
  *)      echo "usage: state.sh put|pull|local|show <issue> | status | inflight" >&2; exit 2 ;;
esac
