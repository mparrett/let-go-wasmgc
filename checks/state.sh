#!/usr/bin/env bash
# checks/state.sh — an issue's workflow state, init.d style: numbered entries
# read in lexical order (00_governance first, 99_next_action last), each an
# RFC 822 header block and a body.
#
#   state.sh put <issue> <state>   post stdin as the <state> entry: a
#                                  `git issue comment` led by `State:` and
#                                  `Kind:` headers. Exit 1 if <state> is a
#                                  latch that is already set. The comment is
#                                  posted as you to a shared tracker, so put
#                                  refuses (exit 3) unless LW_STATE_POST=1.
#   state.sh pull <issue>          rebuild $LW_STATE/<issue>/<state>.md from
#                                  the issue's comments and print the dir
#   state.sh show <issue>          pull, then print every entry in boot order
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
# The issue is the store: comments are append-only and travel with the
# issue's notes, so the state reaches every machine and agent the issue does.
# $LW_STATE (checks/env.sh) is only a cache for cat at boot; delete it freely.
# The kind of each state is fixed by the table below, never by the comment:
# comments are written by whoever can comment, so they are data.
#   latch       the first entry wins; a later one is reported and ignored
#   transition  the latest entry wins
#   append      every entry, oldest first
set -uo pipefail
. "$(dirname "$0")/env.sh"

kinds='00_governance latch
05_inflight latch
10_issue latch
15_facts append
18_baseline latch
20_plan latch
30_rows append
32_jobs append
35_gate transition
40_review transition
45_review_ok transition
50_commit transition
60_push transition
90_retro latch
99_next_action transition'

kind_of() { printf '%s\n' "$kinds" | awk -v s="$1" '$1==s{print $2}'; }

gi() { git issue "$@" 2>/dev/null; }

# Every state entry of an issue as records separated by NUL: the first line is
# the state name, the rest is the entry as posted. Porcelain prints a comment
# as `comment: [<time>] <author>: <first line>` and each further line with a
# one-space prefix, so a body line can never pass for a new field.
entries() {
  gi show "$1" --porcelain | awk '
    function flush() { if (st != "") printf "%s\n%s%c", st, body, 0; st = ""; body = "" }
    /^comment: / {
      flush(); in_c = 1
      line = $0; sub(/^comment: \[[^]]*\] [^:]*: /, "", line)
      if (line ~ /^State: [0-9][0-9]_[a-z0-9_]+$/) { st = substr(line, 8); body = line "\n" } else in_c = 0
      next }
    /^ / { if (in_c && st != "") body = body substr($0, 2) "\n"; next }
    { flush(); in_c = 0 }
    END { flush() }'
}

pull() {
  local issue=$1 dir tmp st entry kind
  dir=$LW_STATE/$issue; tmp=$(mktemp -d "$LW_STATE/.pull.XXXXXX") || return 2
  gi show "$issue" --porcelain >/dev/null || { echo "state: no issue $issue" >&2; rm -rf "$tmp"; return 2; }
  while IFS= read -r -d '' entry; do
    st=${entry%%$'\n'*}; entry=${entry#*$'\n'}
    kind=$(kind_of "$st")
    case $kind in
      latch) if [ -e "$tmp/$st.md" ]; then echo "state: $issue $st is a latch; ignoring a later entry" >&2
             else printf '%s' "$entry" > "$tmp/$st.md"; fi ;;
      transition) printf '%s' "$entry" > "$tmp/$st.md" ;;
      append) { [ -e "$tmp/$st.md" ] && echo; printf '%s' "$entry"; } >> "$tmp/$st.md" ;;
      *) echo "state: $issue: unknown state $st, ignored" >&2 ;;
    esac
  done < <(entries "$issue")
  rm -rf "$dir"; mv "$tmp" "$dir"; echo "$dir"
}

put() {
  local issue=$1 st=$2 kind body dir
  kind=$(kind_of "$st"); [ -n "$kind" ] || { echo "state: unknown state $st" >&2; return 2; }
  [ "${LW_STATE_POST:-0}" = 1 ] || { echo "state: put posts to the issue; set LW_STATE_POST=1 to allow" >&2; return 3; }
  dir=$(pull "$issue" 2>/dev/null) || return 2
  if [ "$kind" = latch ] && [ -e "$dir/$st.md" ]; then echo "state: $issue $st is latched" >&2; return 1; fi
  body=$(cat)
  gi comment "$issue" "$(printf 'State: %s\nKind: %s\n%s' "$st" "$kind" "$body")" >/dev/null || return 2
  pull "$issue" >/dev/null 2>&1
}

show() {
  local dir f; dir=$(pull "$1") || return 2
  for f in "$dir"/*.md; do [ -e "$f" ] || continue; printf '==> %s <==\n' "${f##*/}"; cat "$f"; echo; done
}

status() {
  local issue f
  for issue in $(gi list --porcelain | awk -F'\t' '$3!="closed"{print $2}'); do
    f=$(pull "$issue" 2>/dev/null)/99_next_action.md; [ -e "$f" ] || continue
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
  echo 'Row: A' | put "$id" 30_rows; echo 'Row: B' | put "$id" 30_rows
  check 'append keeps both, oldest first' '[ "$(grep ^Row: "$LW_STATE/$id/30_rows.md" | tr "\n" " ")" = "Row: A Row: B " ]'
  echo x | put "$id" 77_bogus 2>/dev/null; rc=$?
  check 'unknown state refused' '[ $rc = 2 ]'
  check 'show prints in boot order' '[ "$(show "$id" | grep "^==>" | tr -d "=<> " | tr "\n" " ")" = "10_issue.md 30_rows.md 99_next_action.md " ]'
  rm -rf "$LW_STATE/$id"
  check 'cache rebuilt from the issue alone' '[ "$(pull "$id")" = "$LW_STATE/$id" ] && [ -e "$LW_STATE/$id/30_rows.md" ]'
  check 'status reads the readerboard' '[ "$(status)" = "$(printf "%s\tAWAITING_DECLARATION\tapproved-review" "$id")" ]'
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
  put|pull|show|status) mkdir -p "$LW_STATE" ;;
esac
case ${1:-} in
  put)    put "${2:?issue}" "${3:?state}" ;;
  pull)   pull "${2:?issue}" ;;
  show)   show "${2:?issue}" ;;
  status) status ;;
  inflight) inflight ;;
  '')     selftest ;;
  *)      echo "usage: state.sh put|pull|show <issue> | status | inflight" >&2; exit 2 ;;
esac
