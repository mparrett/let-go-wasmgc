#!/usr/bin/env bash
# checks/quiet.sh <cmd...>  — run a timing-sensitive <cmd> on a quiet machine.
#
# A measurement (a hyperfine run, a compile-time bound such as P12.37's WARM)
# taken while other agents' builds run measures their load, not our change.
# Two pools hand out this machine's CPU, and a quiet run must drain both:
#   1. bench-baton (let-go's cmd/bench-baton, pool "letgo"), which the let-go
#      agents use: we take its exclusive lane, so their shared work drains and
#      a waiting exclusive closes the gate to new shared work;
#   2. checks/sem.sh's slots, which this repo's gates use: we take all LW_SLOTS
#      of them, so no slotted command runs while we measure.
# Order is fixed, bench-baton then sem slots, and a quiet run takes the
# $LW_SEM/quiet lock before any slot, so two quiet runs cannot each hold half
# the slots. Calling this under a held slot (LW_SEM_HELD) would wait on our own
# slot, so it refuses: wrap the measured command, never a slotted row.
#
# The command runs un-niced (sem.sh nices builds; a measurement must not be).
# Its output is printed whole after the lease is released, and the exit code is
# the command's. The bench-baton binary is $BENCH_BATON, else bench-baton on
# PATH, else ~/development/let-go/build/bench-baton; without one, only the sem
# slots are drained, with a warning. Waiting for slots is bounded by
# LW_QUIET_WAIT (default 1800 s), after which the command runs anyway with a
# warning, as sem.sh does.
set -uo pipefail
if [ -n "${LW_SEM_HELD:-}" ]; then
  echo "quiet: called under a sem.sh slot; wrap the measured command, not the slotted row" >&2; exit 2
fi
if [ $# -eq 0 ]; then echo "usage: $0 <cmd...>" >&2; exit 2; fi
n=${LW_SLOTS:-4}; d=${LW_SEM:-/tmp/lw-sem-$(id -u)}; d=${d%/}; mkdir -p "$d"

if [ -z "${LW_QUIET_INNER:-}" ]; then
  bb=${BENCH_BATON:-$(command -v bench-baton || true)}
  [ -n "$bb" ] || bb=$HOME/development/let-go/build/bench-baton
  out=$(mktemp); trap 'rm -f "$out"' EXIT
  if [ -x "$bb" ]; then
    LW_QUIET_INNER=1 LW_QUIET_OUT=$out "$bb" bench --owner let-go-wasmgc --intent "quiet: $*" --cwd "$PWD" \
      -- "$0" "$@" > /dev/null
    rc=$?
  else
    echo "quiet: no bench-baton binary, draining sem slots only" >&2
    LW_QUIET_INNER=1 LW_QUIET_OUT=$out "$0" "$@"; rc=$?
  fi
  cat "$out"
  exit $rc
fi

# inner: under bench-baton's exclusive lane (or alone); take the quiet lock,
# then every sem slot, then run
deadline=$(( $(date +%s) + ${LW_QUIET_WAIT:-1800} ))
held=()
release() { local s; for s in ${held[@]+"${held[@]}"}; do rm -rf "$s"; done; }
trap release EXIT
trap 'exit 130' INT; trap 'exit 143' TERM HUP
# sem.sh's reclaim: a slot whose holder died, or that never recorded a pid
reclaim() {
  local s=$1 p dead=$1.dead.$$
  p=$(cat "$s/pid" 2>/dev/null)
  if [ -n "$p" ]; then kill -0 "$p" 2>/dev/null && return; else
    [ $(( $(date +%s) - $(stat -f %m "$s" 2>/dev/null || echo 0) )) -gt 5 ] || return
  fi
  command mv "$s" "$dead" 2>/dev/null || return
  p=$(cat "$dead/pid" 2>/dev/null)
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then command mv "$dead" "$s" 2>/dev/null || true; return; fi
  rm -rf "$dead"
}
# take each of $@ in turn, keeping what we hold (progress is monotone)
take() {
  local s
  for s in "$@"; do
    until mkdir "$s" 2>/dev/null; do
      reclaim "$s"
      if [ "$(date +%s)" -ge "$deadline" ]; then echo "quiet: waited ${LW_QUIET_WAIT:-1800}s for $s, running anyway" >&2; return; fi
      sleep 0.5
    done
    echo $$ > "$s/pid"; held+=("$s")
  done
}
slots=(); for ((i=0;i<n;i++)); do slots+=("$d/slot$i"); done
take "$d/quiet"
take "${slots[@]}"
"$@" > "$LW_QUIET_OUT" 2>&1
