#!/usr/bin/env bash
# checks/sem.sh <cmd...>  — run <cmd> holding one of N machine-wide slots.
#
# The laptop has 8 cores (4 performance). Measured 2026-10-01: the same
# check (checks/run-intrinsics-native.sh, default tier) takes 90 s at load
# 10 and 525 s at load 29-47, and the oracle compile of one program goes
# from 8 s to 30 s. Three agents each running a serial gate already
# oversubscribe the machine; a parallel gate per agent would make it worse.
# So parallelism is granted by ONE pool shared by every agent and every
# script, not per script: LW_SLOTS (default 4) tokens in $LW_SEM
# (default /tmp/lw-sem, outside any watched or per-session tree).
#
# mkdir is the atomic primitive (no flock on macOS bash 3). A slot is a
# directory holding the holder's pid; a slot whose pid is dead is reclaimed,
# so a killed agent cannot wedge the pool. Wait is a 0.5 s poll, bounded
# by LW_SEM_WAIT (default 1800 s), after which the command runs anyway with
# a warning (never silently deadlock a gate).
#
# Use: wrap every lg/node/wasm-tools heavy step, e.g. in run-corpus-par.sh's
# xargs worker:  checks/sem.sh checks/oracle.sh "$f"
set -uo pipefail
n=${LW_SLOTS:-4}; d=${LW_SEM:-/tmp/lw-sem}; mkdir -p "$d"
deadline=$(( $(date +%s) + ${LW_SEM_WAIT:-1800} ))
got=""
while [ -z "$got" ]; do
  for ((i=0;i<n;i++)); do
    s=$d/slot$i
    if mkdir "$s" 2>/dev/null; then echo $$ > "$s/pid"; got=$s; break; fi
    p=$(cat "$s/pid" 2>/dev/null)
    if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then rm -rf "$s"; fi   # dead holder
  done
  [ -n "$got" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then echo "sem: waited ${LW_SEM_WAIT:-1800}s, running unslotted" >&2; break; fi
  sleep 0.5
done
trap '[ -n "$got" ] && rm -rf "$got"' EXIT
"$@"
