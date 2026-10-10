#!/usr/bin/env bash
# checks/sem.sh <cmd...>  — run <cmd> holding one of N machine-wide slots.
#
# The laptop has 8 cores (4 performance). Measured 2026-10-01: the same
# check (checks/run-intrinsics-native.sh, default tier) takes 90 s at load
# 10 and 525 s at load 29-47, and the oracle compile of one program goes
# from 8 s to 30 s. Three agents each running a serial gate already
# oversubscribe the machine; a parallel gate per agent would make it worse.
# So parallelism is granted by ONE pool shared by every agent and every
# script, not per script: LW_SLOTS (default 4) tokens in $LW_SEM. The default,
# /tmp/lw-sem-<uid>, is the same path in every shell, session and TMPDIR, so
# the pool is machine-wide by construction (it used to sit under $TMPDIR,
# which is per session: on 2026-10-08 three agents each had their own four
# slots and the load reached 50). checks/env.sh exports the same default.
# checks/slots.sh lists who holds the slots.
# The held command runs under `nice -n ${LW_NICE:-10}` (an increment on the
# caller's niceness, so 5 becomes 15): builds yield to the
# user's interactive work. It does not change throughput among builds; the
# slot count does.
#
# mkdir is the atomic primitive (no flock on macOS bash 3). A slot is a
# directory holding the holder's pid; a slot whose pid is dead is reclaimed
# (by an atomic rename, so two reclaimers cannot both delete a slot that a
# third has just taken), so a killed agent cannot wedge the pool. Wait is a
# 0.5 s poll, bounded by LW_SEM_WAIT (default 1800 s), after which the command
# runs anyway with a warning (never silently deadlock a gate).
#
# Wrap LEAVES (one oracle program, one census shard, one native test file),
# never an orchestrator that itself fans out through the pool: a gate holding
# a slot per row while its rows wait for slots can deadlock four agents'
# gates against each other. As a backstop a command started under a held slot
# sees LW_SEM_HELD=1 and runs without taking another, so accidental nesting
# costs oversubscription, not a deadlock.
set -uo pipefail
if [ -n "${LW_SEM_HELD:-}" ]; then exec "$@"; fi
n=${LW_SLOTS:-4}; d=${LW_SEM:-/tmp/lw-sem-$(id -u)}; d=${d%/}; mkdir -p "$d"
deadline=$(( $(date +%s) + ${LW_SEM_WAIT:-1800} ))
got=""
# a slot whose holder died, or that never recorded a pid (killed between
# mkdir and the write; older than 5 s so a live acquirer is not mistaken)
reclaim() {
  local s=$1 p dead=$1.dead.$$
  p=$(cat "$s/pid" 2>/dev/null)
  if [ -n "$p" ]; then kill -0 "$p" 2>/dev/null && return; else
    [ $(( $(date +%s) - $(stat -f %m "$s" 2>/dev/null || echo 0) )) -gt 5 ] || return
  fi
  command mv "$s" "$dead" 2>/dev/null || return
  # re-check what we actually moved: another reclaimer may have refilled the slot
  p=$(cat "$dead/pid" 2>/dev/null)
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then command mv "$dead" "$s" 2>/dev/null || true; return; fi
  rm -rf "$dead"
}
while :; do
  for ((i=0;i<n;i++)); do
    s=$d/slot$i
    if mkdir "$s" 2>/dev/null; then echo $$ > "$s/pid"; got=$s; break; fi
    reclaim "$s"
  done
  [ -n "$got" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then echo "sem: waited ${LW_SEM_WAIT:-1800}s, running unslotted" >&2; break; fi
  sleep 0.5
done
trap '[ -n "$got" ] && rm -rf "$got"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM HUP
LW_SEM_HELD=1 nice -n "${LW_NICE:-10}" "$@"
exit $?
