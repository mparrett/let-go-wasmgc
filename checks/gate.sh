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
# in a reason is written `\#`, and a backslash `\\`. An empty phase prints
# `1..0`. The plan line `1..N` comes first; there is no version line. The gate
# exits 1 when anything fails.
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
[ ${#ids[@]} -gt 0 ] || { echo "1..0"; exit 0; }

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
row() {
  if [ "${LW_ATTEST:-1}" != 0 ] && checks/attest.sh fresh "$1" 2>/dev/null; then
    : >"$rcd/$1.att"; echo 0 >"$rcd/$1.tmp"; command mv "$rcd/$1.tmp" "$rcd/$1.rc"; return
  fi
  LW_ITEMS=$items checks/run.sh "$1" >"$logd/$1.log" 2>&1
  rc=$?; [ $rc = 0 ] && [ "${LW_ATTEST:-1}" != 0 ] && checks/attest.sh record "$1" 2>/dev/null
  echo $rc >"$rcd/$1.tmp"; command mv "$rcd/$1.tmp" "$rcd/$1.rc"
}
export -f row
printf '%s\0' "${ids[@]}" | xargs -0 -n 1 -P "$j" bash -c 'row "$1"' _ &
xp=$!
# `#` would start a TAP directive inside a description or a reason
tapesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/#/\\#/g'; }
echo "1..${#ids[@]}"
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
done
wait "$xp" 2>/dev/null; xp=""
exit $fail
