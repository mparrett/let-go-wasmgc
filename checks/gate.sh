#!/usr/bin/env bash
# checks/gate.sh <phase> — run the phase's rows and report them as TAP.
#
# A row's exit: 0 passes; 1 fails; 2 is skipped, but only when the last line
# of the row's output starts with SKIP, and that line is the reason
# (`ok n - <id> # SKIP <reason>`); 3 is not built yet. A row whose items.tsv column 5 names an
# owning issue is known to fail: any non-zero exit prints
# `not ok n - <id> # TODO git-issue:<issue>` and passes, and a 0 prints TAP's
# bonus `ok n - <id> # TODO …` and fails the gate, since the issue's entry is
# then stale. Exit 3 without an owning issue, exit 2 whose last line is not a
# SKIP line (the word SKIP, then a space or the line's end), and 1 fail. A `#`
# in a reason is written `\#`, and a backslash `\\`. The stream is TAP 13: the
# version line, then the plan line `1..N` (`1..0` for an empty phase), then
# each row's line and under it a YAML block: `duration_ms`, the row's wall time
# less the time it was blocked on the slot pool (an attested row's is the time
# its freshness check took), and that blocked time, `wait_ms`. Two rows that
# run at once (LW_GATE_J) still share the machine, so rank rows by cost from a
# quiet run with LW_GATE_J=1. A row that runs a gate itself does not see its
# inner rows' waits, which the inner gate traces per row, so they count as its
# work. The gate exits 1 when anything fails.
#
# Each row also appends one line to the timings ledger, $LW_GATE_TIMES
# (default $LW_STATE/gate-times.tsv, per machine and untracked): when the gate
# started (UTC), the revision (+edits when the tree has changes), the host, the
# phase, the row, its exit, duration_ms, wait_ms, attested (1 or 0), the
# LW_GATE_J it ran under, and the 1-minute load average and the slots held
# (checks/sem.sh) when the gate started. A row is logged when its line prints,
# so an interrupted gate logs only the rows it printed. A ledger with another
# header (an older format) is moved aside to <ledger>.<time>.old, and a new
# one is started.
#
# D106 (1c): the phase's rows run LW_GATE_J at a time (default 2; 1 = one
# after another), and their lines come in items.tsv order (printed as soon as
# a row and every row before it have finished). The difference from the old serial gate: each
# row's output is KEPT in ${TMPDIR:-/tmp}/lw-gate-<phase>/<id>.log instead of
# discarded, so a failing row says where to look (on stderr, so the TAP is unchanged)
# rather than meaning "rerun the row to see why". Two gates of the same phase
# running at once share that directory and overwrite each other's logs.
# Rows are not wrapped in the slot pool (checks/sem.sh) themselves: a gate
# holding a slot per row while the rows' own workers wait for slots could
# deadlock several agents' gates against each other. The heavy leaves
# (oracle programs, census shards, native test files) take slots instead.
set -uo pipefail
cd "$(dirname "$0")/.."
ph=${1:?phase}; fail=0
# D51: the gate runs the slow tier too. SLOW=1 makes the native runtime check
# (P2.9's row) run its default assertions plus the 10k map/set builds, every
# path at 1000 keys and the 1e6 reduce gate, so one pass covers both tiers.
[ "$ph" = 2 ] && export SLOW=1
j=${LW_GATE_J:-2}
case $j in ''|*[!0-9]*|0) echo "LW_GATE_J must be a positive integer (got '$j')" >&2; exit 2;; esac
. "$(dirname "$0")/env.sh"
# LW_ITEMS: another items file, for the gate's own self-test (a relative path
# is read from the repository root)
items=${LW_ITEMS:-checks/items.tsv}
ids=()
while IFS= read -r id; do ids+=("$id"); done < <(awk -F'\t' -v p="$ph" '$1 !~ /^#/ && $2==p && $1 !~ /GATE/{print $1}' "$items")
# rows of a later phase this gate also runs: P10.3 is a browser page check
# beside P7.5's (D194)
case $ph in 7) ids+=(P10.3) ;; esac
if [ -n "${LW_GATE_ROWS:-}" ]; then ids=(); for id in $LW_GATE_ROWS; do ids+=("$id"); done; fi   # test hook (attest.sh)
[ ${#ids[@]} -gt 0 ] || { printf 'TAP version 13\n1..0\n'; exit 0; }
# the run's conditions, taken before any row starts
times=${LW_GATE_TIMES:-$LW_STATE/gate-times.tsv}
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
rev=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)$([ -z "$(git status --porcelain 2>/dev/null)" ] || echo +edits)
load1=$(uptime | sed 's/.*load averages*: *//; s/[, ].*//')
held=$(ls -d "$LW_SEM"/slot*/ 2>/dev/null | wc -l | tr -d ' ')
mkdir -p "$(dirname "$times")"
header=$(printf 'started\trev\thost\tphase\trow\texit\tduration_ms\twait_ms\tattested\tjobs\tload1\tslots_held')
[ ! -s "$times" ] || [ "$(head -1 "$times")" = "$header" ] || command mv "$times" "$times.$(date -u +%Y%m%dT%H%M%SZ).old"
# noclobber: two first gates at once write one header
[ -s "$times" ] || (set -C; printf '%s\n' "$header" >"$times") 2>/dev/null
host=$(hostname -s 2>/dev/null || uname -n)

logd=${TMPDIR:-/tmp}; logd=${logd%/}/lw-gate-$ph; mkdir -p "$logd"
rcd=$(mktemp -d); xp=""
# stop a whole subtree (xargs -> sem.sh -> worker -> lg), parent first so xargs
# starts no replacement, so an interrupted run
# leaves no workers or held slots behind
killtree() { local c kids; kids=$(pgrep -P "$1" 2>/dev/null); kill "$1" 2>/dev/null; for c in $kids; do killtree "$c"; done; return 0; }
trap 'for c in $(pgrep -P $$ 2>/dev/null); do killtree "$c"; done; rm -rf "$rcd"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM HUP
export logd rcd items
# a check's KEEP=1 prints its kept dir after its last line, which then could not
# be the SKIP reason; the gate keeps each row's log instead
unset KEEP
for id in "${ids[@]}"; do rm -f "$logd/$id.log"; done

# Build the rtlib once before rows fan out: two rows starting cold would each
# build it (45-175 s, CPU only, identical output). Same newer-than guess as
# checks/run-corpus.sh: a wrong guess costs one compile, never a wrong result.
if [ "$j" -gt 1 ] && [ -x checks/wasm-run.sh ]; then
  d=${LW_RTLIB_DIR:-src/.rtlib}
  newest=$(ls -t "$d"/rtlib-${LW_TARGET:-gc}-*.edn 2>/dev/null | head -1)
  if [ -z "$newest" ] || [ -n "$(find src rt/wasm -name '*.lg' -newer "$newest" 2>/dev/null | head -1)" ]; then
    w=$(mktemp -d)
    checks/sem.sh "$LG" -source-paths src src/driver.lg corpus/scalar/fib.clj "$w/m.wat" >/dev/null 2>&1 &
    wait $!   # (background + wait: a TERM during the build reaches the trap at once)
    rm -rf "$w"
  fi
fi

# P5.4: a row whose inputs (checks/attest.sh key) are unchanged since its last
# green run is not rerun; it reports `ok <id> (attested)`. LW_ATTEST=0 runs
# everything (phase-gate decisions are taken that way, see attest.sh header).
# ms since the epoch: bash 5's EPOCHREALTIME, else perl (a process per call)
now_ms() { if [ -n "${EPOCHREALTIME:-}" ]; then local u=${EPOCHREALTIME/[.,]/}; echo $(( u / 1000 )); else perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; fi; }
# the ms a row spent blocked on the slot pool: some sem.sh of the row waiting
# and none holding a slot (its intervals from LW_SEM_TRACE), so a worker that
# waits while another of the row's works is not counted, beyond the up to
# 0.5 s it takes to retry after a release
blocked_ms() {
  [ -s "$1" ] || { echo 0; return; }
  awk '{ e[n++] = $1 " 1 0"; e[n++] = $2 " -1 1"; e[n++] = $3 " 0 -1" }
    END { for (i = 0; i < n; i++) print e[i] }' "$1" | sort -n -k1,1 |
  awk '{ if (NR > 1 && w > 0 && h == 0) b += $1 - t; t = $1; w += $2; h += $3 } END { print b + 0 }'
}
# a row's work time (wall minus blocked) and blocked time go to
# $rcd/<id>.ms and <id>.wait before its exit to <id>.rc, which the output
# loop waits for
row() {
  local t0 w; t0=$(now_ms); export LW_SEM_TRACE=$rcd/$1.sem
  if [ "${LW_ATTEST:-1}" != 0 ] && checks/attest.sh fresh "$1" 2>/dev/null; then
    : >"$rcd/$1.att"; echo $(( $(now_ms) - t0 )) >"$rcd/$1.ms"; echo 0 >"$rcd/$1.wait"
    echo 0 >"$rcd/$1.tmp"; command mv "$rcd/$1.tmp" "$rcd/$1.rc"; return
  fi
  LW_ITEMS=$items checks/run.sh "$1" >"$logd/$1.log" 2>&1
  rc=$?; w=$(blocked_ms "$rcd/$1.sem"); echo $(( $(now_ms) - t0 - w )) >"$rcd/$1.ms"; echo "$w" >"$rcd/$1.wait"
  [ $rc = 0 ] && [ "${LW_ATTEST:-1}" != 0 ] && checks/attest.sh record "$1" 2>/dev/null
  echo $rc >"$rcd/$1.tmp"; command mv "$rcd/$1.tmp" "$rcd/$1.rc"
}
export -f row now_ms blocked_ms
printf '%s\0' "${ids[@]}" | xargs -0 -n 1 -P "$j" bash -c 'row "$1"' _ &
xp=$!
# `#` would start a TAP directive inside a description or a reason
tapesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/#/\\#/g'; }
printf 'TAP version 13\n1..%s\n' "${#ids[@]}"
n=0
for id in "${ids[@]}"; do
  n=$((n + 1))
  while [ ! -e "$rcd/$id.rc" ]; do
    kill -0 "$xp" 2>/dev/null || break
    sleep 0.3
  done
  rc=$(cat "$rcd/$id.rc" 2>/dev/null || echo 99)
  issue=$(awk -F'\t' -v id="$id" '$1==id{print $5; exit}' "$items")
  att=""; [ -e "$rcd/$id.att" ] && att=" (attested)"
  if [ -n "$issue" ]; then
    if [ "$rc" = 0 ]; then
      echo "ok $n - $(tapesc "$id")$att # TODO git-issue:$issue passes now; its issue is stale"; fail=1
    else
      echo "not ok $n - $(tapesc "$id") # TODO git-issue:$issue (exit $rc)"
    fi
  elif [ "$rc" = 0 ]; then
    echo "ok $n - $(tapesc "$id")$att"
  elif [ "$rc" = 2 ] && reason=$(tail -n 1 "$logd/$id.log" 2>/dev/null | grep -E '^SKIP( |$)'); then
    echo "ok $n - $(tapesc "$id") # SKIP $(tapesc "${reason#SKIP}" | sed 's/^[[:space:]]*//')"
  else
    case $rc in 2) why="exit 2, and its last line is not a SKIP line" ;; 3) why="not built, and no owning issue in items.tsv" ;; *) why="exit $rc" ;; esac
    echo "not ok $n - $(tapesc "$id") ($why)"; echo "gate: $id output kept in $logd/$id.log" >&2; fail=1
  fi
  ms=$(cat "$rcd/$id.ms" 2>/dev/null); case $ms in ''|*[!0-9]*) ms=null ;; esac
  wt=$(cat "$rcd/$id.wait" 2>/dev/null); case $wt in ''|*[!0-9]*) wt=null ;; esac
  printf '  ---\n  duration_ms: %s\n  wait_ms: %s\n  ...\n' "$ms" "$wt"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$started" "$rev" "$host" "$ph" "$id" "$rc" "$ms" "$wt" \
    "$([ -e "$rcd/$id.att" ] && echo 1 || echo 0)" "$j" "$load1" "$held" >>"$times"
done
wait "$xp" 2>/dev/null; xp=""
exit $fail
