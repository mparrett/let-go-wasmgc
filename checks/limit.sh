#!/usr/bin/env bash
# checks/limit.sh <step> <cmd> [args...] — run one step of a corpus program
# (run = a native or backend run of the program, compile = the driver) under
# the limits checks/run-corpus.sh sets for that program, and exit with the
# command's status.
#
# LW_LIMIT_RUN="<cpu-s> <wall-s>" and LW_LIMIT_COMPILE="<wall-s>"; a step
# whose variable is unset runs unlimited (any caller but run-corpus.sh).
# The CPU limit is a watcher, not `ulimit -t`: macOS only sends SIGXCPU,
# which the Go runtime ignores, so a looping lg ran 80 s past a 2 s ulimit.
# The clock limit is GNU timeout, which kills the step's process group.
# An over-limit step exits 124 and writes `TIMEOUT <step> <kind> <limit>s`
# to LW_LIMIT_LOG; every limited step also writes `<step> <wall-s> <cpu-s>`
# there, which run-corpus.sh sums for its suite cap.
set -uo pipefail
step=${1:?usage: limit.sh <run|compile> <cmd>...}; shift
case $step in
  run) spec=${LW_LIMIT_RUN:-} ;;
  compile) spec=${LW_LIMIT_COMPILE:-}; [ -n "$spec" ] && spec="0 $spec" ;;
  *) echo "limit.sh: unknown step $step" >&2; exit 2 ;;
esac
[ -n "$spec" ] || exec "$@"
read -r cpu wall <<<"$spec"
log=${LW_LIMIT_LOG:-/dev/null}

# ps prints cputime as [[dd-]hh:]mm:ss.cc
secs() { awk -F'[-:]' '{s=0; for (i=1;i<=NF;i++) s=s*60+$i; print s}' <<<"$1"; }
now() { echo "${EPOCHREALTIME:-$SECONDS}"; }

t0=$(now)
timeout -k 5 "$wall" "$@" 0<&0 &
pid=$!
trap 'kill -TERM -- -"$pid" 2>/dev/null; exit 143' TERM INT HUP
used=0 over=""
while kill -0 "$pid" 2>/dev/null; do
  sleep 0.2
  [ "$cpu" = 0 ] && continue
  c=$(pgrep -P "$pid" | head -1)
  [ -n "$c" ] || continue
  t=$(ps -o cputime= -p "$c" 2>/dev/null) || continue
  used=$(secs "${t// /}")
  if awk -v u="$used" -v l="$cpu" 'BEGIN{exit !(u > l)}'; then
    over=cpu
    kill -KILL -- -"$pid" 2>/dev/null
    break
  fi
done
{ wait "$pid"; } 2>/dev/null; rc=$?  # no "Killed: 9" notice on stderr
el=$(awk -v a="$t0" -v b="$(now)" 'BEGIN{printf "%.2f", b-a}')
echo "$step $el $used" >>"$log"
if [ -n "$over" ]; then
  echo "TIMEOUT $step cpu ${cpu}s" >>"$log"; exit 124
elif [ $rc -eq 124 ] || { [ $rc -eq 137 ] && awk -v e="$el" -v w="$wall" 'BEGIN{exit !(e >= w)}'; }; then
  echo "TIMEOUT $step wall ${wall}s" >>"$log"; exit 124
fi
exit $rc
