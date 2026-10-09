#!/usr/bin/env bash
# checks/slots.sh [--kill-dead] — show who holds the machine-wide slots
# (checks/sem.sh): per held slot the holder pid, age, state, the command it is
# running and where from (its cwd, or the first path with /worktrees/ in the
# command line), then the free count.
# Holders are the sem.sh processes themselves; the command shown is the child
# they run (the lg compile or the test). A dead holder's slot is reclaimed by
# the next sem.sh that wants one; --kill-dead removes them now.
# Same LW_SLOTS / LW_SEM defaults as sem.sh.
set -uo pipefail
n=${LW_SLOTS:-4}; d=${LW_SEM:-/tmp/lw-sem-$(id -u)}; d=${d%/}
kill_dead=0
case "${1:-}" in
  "") ;;
  --kill-dead) kill_dead=1 ;;
  *) echo "usage: $0 [--kill-dead]" >&2; exit 2 ;;
esac
now=$(date +%s); held=0
for ((i = 0; i < n; i++)); do
  s=$d/slot$i
  [ -d "$s" ] || continue
  p=$(cat "$s/pid" 2>/dev/null || true)
  age=$(( now - $(stat -f %m "$s" 2>/dev/null || echo "$now") ))
  if [ -z "$p" ]; then
    # mkdir done, pid not written yet (or the acquirer died in between)
    printf 'slot%d  pid -      %5ds  starting\n' "$i" "$age"; held=$((held + 1)); continue
  fi
  if ! kill -0 "$p" 2>/dev/null; then
    printf 'slot%d  pid %-7s %5ds  DEAD\n' "$i" "$p" "$age"
    if [ "$kill_dead" = 1 ]; then
      # rename first: a live acquirer cannot lose a slot it just re-took
      command mv "$s" "$s.dead.$$" 2>/dev/null && rm -rf "$s.dead.$$" && echo "        removed slot$i"
    fi
    continue
  fi
  held=$((held + 1))
  # the work is the holder's child; the holder's own line is just sem.sh
  kid=$(pgrep -P "$p" | head -1)
  full=$(ps -o command= -p "${kid:-$p}" 2>/dev/null)
  cmd=$(printf '%s' "$full" | sed "s|$d/||; s|^[^ ]*/||" | cut -c1-100)
  cwd=$(lsof -a -p "${kid:-$p}" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
  # the full line, not the shortened one: the worktree name is what is wanted
  wt=$(printf '%s\n' "$full $(ps -o command= -p "$p" 2>/dev/null)" | grep -o '[^ ]*/worktrees/[^ /]*' | head -1)
  printf 'slot%d  pid %-7s %5ds  run   %s\n        from %s\n' "$i" "$p" "$age" "$cmd" "${wt:-${cwd:-unknown}}"
done
echo "held $held of $n, free $((n - held)) ($d)"
