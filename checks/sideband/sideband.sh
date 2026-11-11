#!/usr/bin/env bash
# checks/sideband/sideband.sh — attention pings between two owners' agents
# over the public OpenDHT network (git-issue:ac94ed2). A ping is
# `<git-issue id> <tip of refs/notes/issue-<id>>`, SSH-signed: it only shortens
# the wait for the next notes sync. The hourly notes poll stays the floor;
# nothing an agent does depends on a ping arriving.
#
#   sideband.sh init                 make this owner's co-signing and issuer keys:
#                                    private halves into the OS key store, public
#                                    halves to keys/<owner>-cosign.pub and
#                                    keys/<owner>-issuer.pub
#   sideband.sh cosign <peer>        (by hand; the key store asks each time) sign
#                                    <peer>'s issuer key with our co-signing key:
#                                    keys/<peer>-issuer.by-<owner>.sig
#   sideband.sh start                load the issuer key into a private ssh-agent
#                                    (once, at launch) and issue a ping key
#   sideband.sh stop                 end the agent: the issuer and ping keys go with it
#   sideband.sh rotate               a fresh ping key with an LW_SIDEBAND_TTL
#                                    certificate (send rotates when it has lapsed)
#   sideband.sh send [--when-present] <peer> <issue>
#                                    sign a ping for an open issue and put it,
#                                    once, on <peer>'s topic (no retry); with
#                                    --when-present, hold that one put until
#                                    <peer>'s presence token is current, giving up
#                                    after LW_SIDEBAND_HOLD
#   sideband.sh listen               listen on our own topic; each verified ping
#                                    joins the queue; publish our presence token
#   sideband.sh presence <peer>      exit 0 when <peer>'s presence token is current
#   sideband.sh wait [<issue>...]    block while no ping (for one of these issues) is
#                                    pending, then print one and exit: a session's
#                                    background command, so a ping wakes the session
#   sideband.sh pending              the queue: `<peer> <issue> <notes commit>`
#   sideband.sh done <issue> [<c>]   drop an issue's ping (only commit <c>'s) once read
#   sideband.sh                      self-test (offline, a throwaway key store)
#
# Keys, after LOAS: three per owner. The co-signing key is human-only: its key
# store item trusts no program, so every use asks the owner, and it never enters
# the agent. The issuer key is unattended: read once at start into a private
# ssh-agent, it certifies short-lived ping keys there (ssh-keygen -U), never on
# disk. A ping key lives only in the agent, with a certificate for
# LW_SIDEBAND_TTL (20h) that the agent forgets when it ends.
#
# Trust: a ping is accepted only when its key holds a current certificate from
# the sender's issuer key, for the sender's name and the "lw-sideband"
# namespace, and the recipient's own co-signing key has signed that issuer key.
# Co-signatures are committed by reviewed PR; removing one stops the channel.
# A ping names an issue that exists and is open; it never opens a topic. A
# listener queues at most LW_SIDEBAND_DEPTH (2) pending issues per peer and
# drops the rest. Both sides log what they send and receive.
#
# Presence: while it runs, listen keeps `present <owner> <unix time>` on
# let-go-wasmgc/sideband/presence/<owner>, signed with the ping key under its
# own namespace ("lw-sideband-presence"), so a token never verifies as a ping
# or the reverse. The token is a persistent put (dhtnode's pp), which the node
# re-announces while it runs; every five minutes a heartbeat cancels it by its
# value id (cpp) and puts one with a fresh time, since a second pp adds a value
# rather than replacing the first. Shutdown cancels the last one. A value on
# OpenDHT expires about ten minutes after its last announce, and a token older
# than fifteen minutes counts as absent, so a stopped listener drops out.
# Presence decides only when a ping is sent, never whether one is trusted.
#
# Key store: the macOS Keychain (security) or, on Linux, libsecret's
# secret-tool; a headless Linux host would need another backend, such as the
# kernel keyring (keyctl). Secrets cross argv never: security -i reads its
# command on stdin, and a private key reaches ssh-keygen and ssh-add through a
# mode-600 FIFO. A new ping key is written once to a mode-700 temporary
# directory, loaded, and removed.
#
# Env: LW_SIDEBAND_OWNER (our name, required), LW_SIDEBAND_TTL (default 20h),
# LW_SIDEBAND_STATE (agent socket, queue, logs), LW_SIDEBAND_KEYS (default
# checks/sideband/keys), LW_SIDEBAND_DEPTH, LW_SIDEBAND_BOOTSTRAP (default
# bootstrap.jami.net), LW_SIDEBAND_HOLD (default 2h). Needs OpenSSH 8.2+, and
# dhtnode (OpenDHT) for send, listen and presence.
set -uo pipefail
cd "$(dirname "$0")/../.."

NS=lw-sideband
PNS=$NS-presence
PRESENCE_EVERY=${LW_SIDEBAND_PRESENCE_EVERY:-300}   # seconds between heartbeats
PRESENCE_MAX=900                      # a token older than this counts as absent
KEYS=${LW_SIDEBAND_KEYS:-checks/sideband/keys}
STATE=${LW_SIDEBAND_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/let-go-wasmgc/sideband}
DEPTH=${LW_SIDEBAND_DEPTH:-2}
TTL=${LW_SIDEBAND_TTL:-20h}
HOLD=${LW_SIDEBAND_HOLD:-2h}
BOOT=${LW_SIDEBAND_BOOTSTRAP:-bootstrap.jami.net}
STORE=${LW_SIDEBAND_STORE:-}          # a directory: the self-test's throwaway store
ME=${LW_SIDEBAND_OWNER:-}

die() { echo "sideband: $*" >&2; exit 1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
need_me() { [ -n "$ME" ] || die "set LW_SIDEBAND_OWNER to this owner's name"; name_ok "$ME" || die "owner name must match [a-z0-9_]+"; }
name_ok() { case $1 in ''|*[!a-z0-9_]*) return 1 ;; esac; }
ttl_seconds() { case $1 in *h) echo $(( ${1%h} * 3600 )) ;; *m) echo $(( ${1%m} * 60 )) ;; *s) echo "${1%s}" ;; *) echo "$1" ;; esac; }

# --- key store: put <name> <human-only?> (secret on stdin), get <name> --------
ks_put() {
  local v; v=$(base64 | tr -d '\n')
  if [ -n "$STORE" ]; then printf '%s' "$v" > "$STORE/$1"; chmod 600 "$STORE/$1"
  elif [ "$(uname)" = Darwin ]; then
    # -T "" trusts no program, so every read of a human-only item asks the owner
    local acl=""; [ "$2" = human ] && acl='-T ""'
    printf 'add-generic-password -U -s lw-sideband -a %s -l "lw-sideband %s" %s -w %s\n' "$1" "$1" "$acl" "$v" | security -i >/dev/null
  elif command -v secret-tool >/dev/null; then
    # libsecret has no per-read prompt: any process of the owner can read an
    # unlocked keyring, so it can hold the issuer key but not the co-signing key
    [ "$2" = human ] && die "libsecret cannot ask on each use: keep the co-signing key on a store that does"
    printf '%s' "$v" | secret-tool store --label="lw-sideband $1" service lw-sideband name "$1"
  else die "no key store: the macOS Keychain or libsecret's secret-tool"; fi
}
ks_get() {
  if [ -n "$STORE" ]; then cat "$STORE/$1"
  elif [ "$(uname)" = Darwin ]; then security find-generic-password -s lw-sideband -a "$1" -w 2>/dev/null
  else secret-tool lookup service lw-sideband name "$1" 2>/dev/null
  fi | base64 -d
}
ks_fifo() { mkfifo -m 600 "$1/k"; (ks_get "$2" > "$1/k" &); }   # <dir> <name>: <dir>/k carries it once

agent_env() { export SSH_AUTH_SOCK=$STATE/agent.sock; }
agent_up() { agent_env; ssh-add -l >/dev/null 2>&1; [ $? -ne 2 ]; }

# --- envelope --------------------------------------------------------------
envelope() {   # <issue> -> `<issue> <notes commit>`, or dies
  local issue=$1 status tip remote
  status=$(git issue show "$issue" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^status: //p')
  [ -n "$status" ] || die "no issue $issue (a ping never opens a topic)"
  case $status in closed|deferred|done) die "issue $issue is $status: a ping only names an open issue" ;; esac
  tip=$(git rev-parse --verify -q "refs/notes/issue-$issue") || die "issue $issue has no notes ref"
  # the peer fetches from the remote, so the ping waits until the note is there
  remote=$(git ls-remote "${LW_SIDEBAND_REMOTE:-origin}" "refs/notes/issue-$issue" | cut -f1)
  [ "$remote" = "$tip" ] || { [ -n "$remote" ] && git merge-base --is-ancestor "$tip" "$remote" 2>/dev/null; } \
    || die "issue $issue's note $tip is not pushed yet: push it, then send"
  printf '%s %s' "$issue" "$tip"
}
sign() {       # <payload> <certificate> [<namespace>] -> one line (payload and signature)
  local t; t=$(mktemp -d)
  printf '%s' "$1" > "$t/p"
  ssh-keygen -q -Y sign -n "${3:-$NS}" -f "$2" "$t/p" </dev/null >/dev/null 2>&1 || { rm -rf "$t"; return 1; }
  { printf '%s\n' "$1"; cat "$t/p.sig"; } | base64 | tr -d '\n'
  rm -rf "$t"
}
cosigned() {   # <peer> <recipient>: the recipient's co-signing key signed the peer's issuer key
  local p=$1 r=$2 t ok=1
  [ -f "$KEYS/$p-issuer.by-$r.sig" ] && [ -f "$KEYS/$r-cosign.pub" ] || return 1
  t=$(mktemp -d)
  printf '%s namespaces="%s-cosign" %s\n' "$r" "$NS" "$(cat "$KEYS/$r-cosign.pub")" > "$t/a"
  ssh-keygen -Y verify -f "$t/a" -I "$r" -n "$NS-cosign" -s "$KEYS/$p-issuer.by-$r.sig" < "$KEYS/$p-issuer.pub" >/dev/null 2>&1 && ok=0
  rm -rf "$t"; return $ok
}
verify_ns() {  # <signed line> <recipient> <namespace> -> `<sender> <payload>`
  local ping=$1 rcpt=$2 ns=$3 t sender payload f p
  t=$(mktemp -d)
  printf '%s' "$ping" | base64 -d > "$t/all" 2>/dev/null || { rm -rf "$t"; echo "not base64"; return 1; }
  head -1 "$t/all" | LC_ALL=C tr -d '\n' > "$t/p"; tail -n +2 "$t/all" > "$t/s"
  : > "$t/allowed"
  for f in "$KEYS"/*-issuer.pub; do
    [ -f "$f" ] || continue; p=$(basename "$f" -issuer.pub); [ "$p" = "$rcpt" ] && continue; name_ok "$p" || continue
    cosigned "$p" "$rcpt" && printf '%s cert-authority,namespaces="%s" %s\n' "$p" "$ns" "$(cat "$f")" >> "$t/allowed"
  done
  sender=$(ssh-keygen -Y find-principals -s "$t/s" -f "$t/allowed" 2>/dev/null | head -1)
  [ -n "$sender" ] || { rm -rf "$t"; echo "not signed under an issuer $rcpt co-signed, or the certificate has lapsed"; return 1; }
  ssh-keygen -Y verify -f "$t/allowed" -I "$sender" -n "$ns" -s "$t/s" < "$t/p" >/dev/null 2>&1 \
    || { rm -rf "$t"; echo "bad signature for $sender"; return 1; }
  payload=$(cat "$t/p"); rm -rf "$t"
  echo "$sender $payload"
}
verify_for() { # <ping> <recipient> -> `<sender> <issue> <commit>`
  local res
  res=$(verify_ns "$1" "$2" "$NS") || { echo "$res"; return 1; }
  printf '%s' "${res#* }" | grep -Eqx '[0-9a-f]{4,40} [0-9a-f]{40}' || { echo "payload is not <issue> <commit>"; return 1; }
  echo "$res"
}

# --- presence ----------------------------------------------------------------
token() {      # <owner> <certificate> [<unix time>] -> a signed presence token
  sign "present $1 ${3:-$(date +%s)}" "$2" "$PNS"
}
present_ok() { # <token> <peer> <recipient>: a current token from <peer>
  local res at age
  res=$(verify_ns "$1" "$3" "$PNS") || return 1
  case $res in "$2 present $2 "*) ;; *) return 1 ;; esac
  at=${res##* }; case $at in ''|*[!0-9]*) return 1 ;; esac
  age=$(( $(date +%s) - at ))
  [ "$age" -le "$PRESENCE_MAX" ] && [ "$age" -ge -60 ]
}
dht_get() {    # <key> -> each value's text, one per line
  (sleep 5; echo "g $1"; sleep 10; echo x) | dhtnode -b "$BOOT" -p 0 2>&1 \
    | sed -n 's/.*Value\[id:[^ ]* data(text\/plain):"\([^"]*\)".*/\1/p'
}
peer_present() { # <peer>
  local v
  for v in $(dht_get "let-go-wasmgc/sideband/presence/$1"); do present_ok "$v" "$1" "$ME" && return 0; done
  return 1
}
hold_until_present() { # <peer>: 0 once its token is current, 1 after HOLD
  local end=$(( $(date +%s) + $(ttl_seconds "$HOLD") ))
  while :; do
    peer_present "$1" && return 0
    [ "$(date +%s)" -lt "$end" ] || { echo "sideband: $1 not present within $HOLD" >&2; return 1; }
    sleep "${LW_SIDEBAND_POLL:-60}"
  done
}

# --- queue: <sender>\t<issue>\t<commit>\t<time>; at most DEPTH per sender -----
enqueue() {
  local sender=$1 issue=$2 commit=$3 q=$STATE/queue.tsv
  mkdir -p "$STATE"; touch "$q"
  if awk -F'\t' -v s="$sender" -v i="$issue" '$1==s && $2==i {f=1} END{exit f?0:1}' "$q"; then
    awk -F'\t' -v OFS='\t' -v s="$sender" -v i="$issue" -v c="$commit" -v n="$(now)" \
      '$1==s && $2==i {$3=c; $4=n} {print}' "$q" > "$q.tmp" && mv "$q.tmp" "$q"
    echo "updated"; return 0
  fi
  if [ "$(awk -F'\t' -v s="$sender" '$1==s' "$q" | wc -l | tr -d ' ')" -ge "$DEPTH" ]; then
    echo "dropped (queue full: $DEPTH pending)"; return 1
  fi
  printf '%s\t%s\t%s\t%s\n' "$sender" "$issue" "$commit" "$(now)" >> "$q"; echo "queued"
}
logline() { mkdir -p "$STATE"; printf '%s\t%s\n' "$(now)" "$2" >> "$STATE/$1.log"; }

# --- commands --------------------------------------------------------------
cmd_init() {
  need_me; local d; d=$(mktemp -d); chmod 700 "$d"
  [ -f "$KEYS/$ME-issuer.pub" ] && { rm -rf "$d"; die "keys/$ME-issuer.pub exists: rotate by hand"; }
  ssh-keygen -q -t ed25519 -N '' -C "$ME co-signing ($NS)" -f "$d/cosign"
  ssh-keygen -q -t ed25519 -N '' -C "$ME issuer ($NS)" -f "$d/issuer"
  { ks_put cosign human < "$d/cosign" && ks_put issuer agent < "$d/issuer"; } || { rm -rf "$d"; die "could not store the keys"; }
  mkdir -p "$KEYS"; cp "$d/cosign.pub" "$KEYS/$ME-cosign.pub"; cp "$d/issuer.pub" "$KEYS/$ME-issuer.pub"
  rm -rf "$d"; echo "keys/$ME-cosign.pub and keys/$ME-issuer.pub written; private halves in the key store"
}
cmd_cosign() {
  need_me; local peer=${1:?usage: cosign <peer>} d
  name_ok "$peer" || die "peer name must match [a-z0-9_]+"
  [ -f "$KEYS/$peer-issuer.pub" ] || die "no keys/$peer-issuer.pub"
  echo "co-signing $peer's issuer key: $(ssh-keygen -lf "$KEYS/$peer-issuer.pub")"
  d=$(mktemp -d); chmod 700 "$d"; cp "$KEYS/$peer-issuer.pub" "$d/issuer.pub"
  # ssh-keygen -Y sign opens its key path twice, so the key goes through a
  # throwaway agent that lives for this one signature
  ks_fifo "$d" cosign
  ( eval "$(ssh-agent -s -a "$d/agent.sock")" >/dev/null
    ssh-add -q "$d/k" </dev/null 2>/dev/null \
      && ssh-keygen -q -Y sign -n "$NS-cosign" -f "$KEYS/$ME-cosign.pub" "$d/issuer.pub" </dev/null >/dev/null 2>&1
    rc=$?; ssh-agent -k >/dev/null 2>&1; exit $rc ) || { rm -rf "$d"; die "co-signing failed"; }
  cp "$d/issuer.pub.sig" "$KEYS/$peer-issuer.by-$ME.sig"; rm -rf "$d"
  echo "keys/$peer-issuer.by-$ME.sig: $peer's issuer key, co-signed by $ME"
}
cmd_start() {
  need_me; local d
  mkdir -p "$STATE"; chmod 700 "$STATE"; agent_env
  agent_up || { rm -f "$SSH_AUTH_SOCK"; eval "$(ssh-agent -s -a "$SSH_AUTH_SOCK")" >/dev/null
                 echo "$SSH_AGENT_PID" > "$STATE/agent.pid"; }
  d=$(mktemp -d); chmod 700 "$d"; ks_fifo "$d" issuer
  ssh-add -q "$d/k" </dev/null 2>/dev/null || { rm -rf "$d"; die "could not load the issuer key"; }
  rm -rf "$d"; cmd_rotate
}
cmd_stop() {
  local pid; pid=$(cat "$STATE/agent.pid" 2>/dev/null)
  [ -n "$pid" ] && [ "$(ps -p "$pid" -o comm= 2>/dev/null | sed 's|.*/||')" = ssh-agent ] && kill "$pid" 2>/dev/null
  rm -f "$STATE/agent.pid" "$STATE/agent.sock" "$STATE/ping-cert.pub"; true
}
cmd_rotate() {
  need_me; local d; agent_env; agent_up || die "no agent: run sideband.sh start"
  d=$(mktemp -d); chmod 700 "$d"
  ssh-keygen -q -t ed25519 -N '' -C "$ME ping ($NS)" -f "$d/ping"
  ssh-keygen -q -s "$KEYS/$ME-issuer.pub" -U -I "$ME ping $(now)" -n "$ME" -V "+$TTL" "$d/ping.pub" </dev/null \
    || { rm -rf "$d"; die "the issuer could not certify a ping key"; }
  ssh-add -q -t "$(ttl_seconds "$TTL")" "$d/ping" </dev/null 2>/dev/null || { rm -rf "$d"; die "could not load the ping key"; }
  cp "$d/ping-cert.pub" "$STATE/ping-cert.pub"; rm -rf "$d"
  echo "ping key certified for $TTL"
}
cert_current() { [ -f "$STATE/ping-cert.pub" ] && ssh-add -l 2>/dev/null | grep "$(ssh-keygen -lf "$STATE/ping-cert.pub" | awk '{print $2}')" >/dev/null; }
cmd_send() {
  local hold=""; [ "${1:-}" = --when-present ] && { hold=1; shift; }
  need_me; local peer=${1:?usage: send [--when-present] <peer> <issue>} issue=${2:?usage: send [--when-present] <peer> <issue>} payload ping out
  name_ok "$peer" || die "peer name must match [a-z0-9_]+"
  command -v dhtnode >/dev/null || die "no dhtnode (OpenDHT) on PATH"
  payload=$(envelope "$issue") || exit 1
  [ -z "$hold" ] || hold_until_present "$peer" || { logline sent "$peer $payload not sent: not present within $HOLD"; exit 1; }
  agent_env; cert_current || cmd_rotate >/dev/null || die "no ping key: run sideband.sh start"
  ping=$(sign "$payload" "$STATE/ping-cert.pub") || die "signing failed"
  out=$( (echo "p let-go-wasmgc/sideband/$peer $ping"; sleep 20; echo x) | dhtnode -b "$BOOT" -p 0 2>&1 | grep -m1 'Put:')
  logline sent "$peer $payload ${out:-no put result}"
  echo "${out:-sideband: put sent, no result seen}"
}
# dhtnode reads its commands from a FIFO, so the heartbeat and the shutdown
# trap both reach it; the reader records each presence put's value id for the
# next cpp
cmd_listen() {
  need_me; local d reader sl
  command -v dhtnode >/dev/null || die "no dhtnode (OpenDHT) on PATH"
  agent_env; mkdir -p "$STATE"; rm -f "$STATE/presence.id"
  d=$(mktemp -d); mkfifo -m 600 "$d/in"
  dhtnode -b "$BOOT" -p 0 < "$d/in" 2>&1 | listen_read & reader=$!
  exec 3> "$d/in"
  trap 'kill $sl 2>/dev/null; presence_cancel; echo x >&3; exec 3>&-; wait $reader; rm -rf "$d"; exit 0' INT TERM
  echo "l let-go-wasmgc/sideband/$ME" >&3
  while :; do
    presence_cancel; presence_put >&3
    sleep "$PRESENCE_EVERY" & sl=$!; wait $sl
  done
}
listen_read() {
  local seen="" line id ping res r
  while IFS= read -r line; do
    case $line in
      *'Put: success'*'Value ID: '*) echo "${line##*Value ID: }" > "$STATE/presence.id"; continue ;;
      *'Value[id:'*'data(text/plain):"'*) ;;
      *) continue ;;
    esac
    id=${line#*Value[id:}; id=${id%% *}
    case " $seen " in *" $id "*) continue ;; esac; seen="$seen $id"
    ping=${line#*data(text/plain):\"}; ping=${ping%%\"*}
    if res=$(verify_for "$ping" "$ME"); then
      set -- $res; r=$(enqueue "$1" "$2" "$3"); logline received "$res $r"
      case $r in queued|updated) prefetch "$2" </dev/null & ;; esac
    else logline received "rejected: $res"; fi
  done
}
# a fresh token each beat, so its age says when the listener last ran; a lapsed
# ping key is rotated first, and a token that cannot be signed is skipped
presence_put() {
  local tok
  cert_current || cmd_rotate >/dev/null 2>&1 || { logline sent "presence skipped: no ping key"; return 0; }
  tok=$(token "$ME" "$STATE/ping-cert.pub") && echo "pp let-go-wasmgc/sideband/presence/$ME $tok"
}
presence_cancel() { # to fd 3: stop re-announcing the last presence put
  local id; id=$(cat "$STATE/presence.id" 2>/dev/null)
  [ -n "$id" ] && echo "cpp let-go-wasmgc/sideband/presence/$ME $id" >&3
  rm -f "$STATE/presence.id"
}
# the note into the prompt hook's watch namespace, so a woken session reads
# it without a fetch of its own; local refs/notes stay untouched
prefetch() {
  git fetch -q --no-tags "${LW_SIDEBAND_REMOTE:-origin}" \
    "+refs/notes/issue-$1:refs/issue-watch/issue-$1" 2>/dev/null || logline received "prefetch of $1 failed"
}
# ids match by prefix either way, so `ac94ed2` and the full id are one issue
same_id() { case $1 in "$2"*) return 0 ;; esac; case $2 in "$1"*) return 0 ;; esac; return 1; }
wanted() { local w; [ -z "$WANT" ] && return 0; for w in $WANT; do same_id "$1" "$w" && return 0; done; return 1; }
# a pending ping is the token: wait returns one for a wanted issue that it
# has not returned before, so a ping that lands while the last one is being
# read is not lost, and one a session ignores without `done` wakes it once
cmd_wait() {
  local q=$STATE/queue.tsv d=$STATE/delivered p i c rest
  while :; do
    if [ -f "$q" ]; then
      while IFS=$'\t' read -r p i c rest; do
        [ -n "$c" ] && wanted "$i" || continue
        grep -qxF "$p $i $c" "$d" 2>/dev/null && continue
        echo "$p $i $c" >> "$d"; echo "$p $i $c"; return 0
      done < "$q"
    fi
    sleep "${LW_SIDEBAND_POLL:-2}"
  done
}
cmd_pending() { [ -f "$STATE/queue.tsv" ] && awk -F'\t' '{print $1, $2, $3}' "$STATE/queue.tsv"; true; }
cmd_done() {   # <issue> [<commit>]: with a commit, only the ping that was read
  local issue=${1:?usage: done <issue> [<commit>]} commit=${2:-} q=$STATE/queue.tsv p i c rest
  [ -f "$q" ] || return 0
  while IFS=$'\t' read -r p i c rest; do
    same_id "$i" "$issue" && { [ -z "$commit" ] || [ "$c" = "$commit" ]; } && continue
    printf '%s\t%s\t%s\t%s\n' "$p" "$i" "$c" "$rest"
  done < "$q" > "$q.tmp" && mv "$q.tmp" "$q"
  [ -f "$STATE/delivered" ] || return 0
  while read -r p i c; do
    same_id "$i" "$issue" && { [ -z "$commit" ] || [ "$c" = "$commit" ]; } && continue
    echo "$p $i $c"
  done < "$STATE/delivered" > "$STATE/delivered.tmp" && mv "$STATE/delivered.tmp" "$STATE/delivered"
}

selftest() {
  local t fail=0 ping res
  t=$(mktemp -d); chmod 700 "$t"
  check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
  run() { local w=$1; shift; (LW_SIDEBAND_STORE=$t/s$w LW_SIDEBAND_KEYS=$t/keys LW_SIDEBAND_STATE=$t/st$w LW_SIDEBAND_OWNER=$w "$0" "$@"); }
  mkdir -p "$t/keys" "$t/sa" "$t/sb" "$t/sc"
  # a and b init and co-sign each other's issuer; c inits, nobody co-signs it
  for w in a b c; do run $w init >/dev/null; done
  run a cosign b >/dev/null; run b cosign a >/dev/null
  check "init keeps private keys out of keys/" '! grep -l PRIVATE "$t"/keys/* >/dev/null 2>&1'
  check "co-signing writes one signature per direction" '[ -f "$t/keys/a-issuer.by-b.sig" ] && [ -f "$t/keys/b-issuer.by-a.sig" ]'
  run a start >/dev/null; run c start >/dev/null
  KEYS=$t/keys
  ping=$(SSH_AUTH_SOCK=$t/sta/agent.sock sign "ac94ed2 3bbf96335929875d56ec4d05872d4c670406c7e9" "$t/sta/ping-cert.pub")
  res=$(verify_for "$ping" b)
  check "b accepts a's ping under a's co-signed issuer" '[ "$res" = "a ac94ed2 3bbf96335929875d56ec4d05872d4c670406c7e9" ]'
  check "c, who co-signed nobody, rejects it" '! verify_for "$ping" c >/dev/null'
  check "a tampered ping is rejected" '! verify_for "$(printf "%s" "$ping" | base64 -d | sed "1s/ac94ed2/0000000/" | base64 | tr -d "\n")" b >/dev/null'
  check "a commit carrying an escaped queue row is rejected" '! verify_for "$(SSH_AUTH_SOCK=$t/sta/agent.sock sign "ac94ed2 3bbf\\nb\\tac94ed2\\tx" "$t/sta/ping-cert.pub")" b >/dev/null'
  check "a payload that is not <issue> <commit> is rejected" '! verify_for "$(SSH_AUTH_SOCK=$t/sta/agent.sock sign "open a new topic" "$t/sta/ping-cert.pub")" b >/dev/null'
  check "a ping under an issuer nobody co-signed is rejected" '! verify_for "$(SSH_AUTH_SOCK=$t/stc/agent.sock sign "ac94ed2 3bbf96335929875d56ec4d05872d4c670406c7e9" "$t/stc/ping-cert.pub")" b >/dev/null'
  # a lapsed certificate: the issuer certifies a ping key for a window already past
  local d; d=$(mktemp -d); ssh-keygen -q -t ed25519 -N '' -f "$d/old"
  SSH_AUTH_SOCK=$t/sta/agent.sock ssh-keygen -q -s "$t/keys/a-issuer.pub" -U -I old -n a -V -2h:-1h "$d/old.pub" </dev/null
  SSH_AUTH_SOCK=$t/sta/agent.sock ssh-add -q "$d/old" </dev/null 2>/dev/null
  check "a ping under a lapsed certificate is rejected" '! verify_for "$(SSH_AUTH_SOCK=$t/sta/agent.sock sign "ac94ed2 3bbf96335929875d56ec4d05872d4c670406c7e9" "$d/old-cert.pub")" b >/dev/null'
  rm -rf "$d"
  # presence: a's listener token, read by b; dht_get is the DHT read, stubbed here
  local tok; tok=$(SSH_AUTH_SOCK=$t/sta/agent.sock token a "$t/sta/ping-cert.pub")
  check "b accepts a's presence token" 'present_ok "$tok" a b'
  check "a stale presence token counts as absent" '! present_ok "$(SSH_AUTH_SOCK=$t/sta/agent.sock token a "$t/sta/ping-cert.pub" $(( $(date +%s) - 3600 )))" a b'
  check "a token under the ping namespace is rejected" '! present_ok "$(SSH_AUTH_SOCK=$t/sta/agent.sock sign "present a $(date +%s)" "$t/sta/ping-cert.pub")" a b'
  check "a ping under the presence namespace is rejected" '! verify_for "$(SSH_AUTH_SOCK=$t/sta/agent.sock sign "ac94ed2 3bbf96335929875d56ec4d05872d4c670406c7e9" "$t/sta/ping-cert.pub" "$PNS")" b >/dev/null'
  check "a token from an issuer nobody co-signed is rejected" '! present_ok "$(SSH_AUTH_SOCK=$t/stc/agent.sock token c "$t/stc/ping-cert.pub")" c b'
  check "a token naming another owner is rejected" '! present_ok "$(SSH_AUTH_SOCK=$t/sta/agent.sock sign "present c $(date +%s)" "$t/sta/ping-cert.pub" "$PNS")" c b'
  dht_get() { cat "$t/dht" 2>/dev/null; }
  : > "$t/dht"
  (sleep 2; printf 'junk\n%s\n' "$tok" > "$t/dht") &
  check "--when-present holds until a token appears" 'ME=b HOLD=10s LW_SIDEBAND_POLL=1 hold_until_present a >/dev/null'
  : > "$t/dht"
  check "--when-present gives up after the hold" '! ME=b HOLD=2s LW_SIDEBAND_POLL=1 hold_until_present a >/dev/null 2>&1'
  # listen against a stand-in dhtnode that logs its commands and answers each
  # pp with a value id, as dhtnode does
  mkdir -p "$t/bin"; cat > "$t/bin/dhtnode" <<'FAKE'
#!/usr/bin/env bash
n=0; while IFS= read -r c; do echo "$c" >> "$FAKE_LOG"
  case $c in pp\ *) n=$((n+1)); echo ">> Put: success, took 0.1 s. Value ID: v$n" ;; x) exit 0 ;; esac; done
FAKE
  chmod +x "$t/bin/dhtnode"
  PATH=$t/bin:$PATH FAKE_LOG=$t/dht.log LW_SIDEBAND_PRESENCE_EVERY=1 \
    LW_SIDEBAND_STORE=$t/sa LW_SIDEBAND_KEYS=$t/keys LW_SIDEBAND_STATE=$t/sta LW_SIDEBAND_OWNER=a "$0" listen & local l=$!
  sleep 4; kill -TERM $l; wait $l 2>/dev/null
  local pk=let-go-wasmgc/sideband/presence/a
  check "listen subscribes to its own topic first" '[ "$(head -1 "$t/dht.log")" = "l let-go-wasmgc/sideband/a" ]'
  check "each heartbeat is a pp of a token b accepts" 'present_ok "$(grep -m1 "^pp $pk " "$t/dht.log" | cut -d" " -f3)" a b && [ "$(grep -c "^pp $pk " "$t/dht.log")" -ge 2 ]'
  check "a heartbeat cancels the previous pp by its id" '[ "$(awk -v k="pp $pk " "f {print; exit} index(\$0, k) == 1 {f = 1}" "$t/dht.log")" = "cpp $pk v1" ]'
  check "shutdown cancels the last pp, then quits" '[ "$(tail -2 "$t/dht.log" | head -1)" = "cpp $pk v$(grep -c "^pp $pk " "$t/dht.log")" ] && [ "$(tail -1 "$t/dht.log")" = x ]'
  check "the ping key lives only in the agent" 'SSH_AUTH_SOCK=$t/sta/agent.sock ssh-add -l | grep "a ping" >/dev/null && ! grep -rl PRIVATE "$t/sta" >/dev/null 2>&1'
  for w in a c; do run $w stop; done
  check "stop ends the agent" '! SSH_AUTH_SOCK=$t/sta/agent.sock ssh-add -l >/dev/null 2>&1' 
  STATE=$t/state
  enqueue a i1 c1 >/dev/null; enqueue a i2 c2 >/dev/null
  check "a third pending issue from one peer is dropped" '! enqueue a i3 c3 >/dev/null'
  check "a newer ping for a queued issue updates it" '[ "$(enqueue a i1 c9)" = updated ] && grep -q "i1	c9" "$t/state/queue.tsv"'
  check "another peer has its own queue" 'enqueue b i1 c1 >/dev/null'
  cmd_done i1
  check "done drops an issue from the queue" '! grep -q "	i1	" "$t/state/queue.tsv"'
  (WANT="i5"; LW_SIDEBAND_POLL=1 cmd_wait > "$t/woke") & local w=$!
  sleep 2; enqueue b i4 c4 >/dev/null; sleep 2
  check "wait ignores a ping for another issue" 'kill -0 $w 2>/dev/null && [ ! -s "$t/woke" ]'
  enqueue b i5 c5 >/dev/null; sleep 3
  check "wait wakes on a new ping for its issue" '! kill -0 $w 2>/dev/null && [ "$(cat "$t/woke")" = "b i5 c5" ]'
  kill $w 2>/dev/null; wait $w 2>/dev/null
  waitfor() { timeout 4 bash -c "$(declare -f cmd_wait wanted same_id); STATE=$STATE; WANT=$1; LW_SIDEBAND_POLL=1; cmd_wait"; }
  check "wait does not return a ping it already returned" '! waitfor i5 >/dev/null'
  enqueue b i5 c6 >/dev/null
  check "a newer commit on a returned issue wakes wait at once" '[ "$(waitfor i5)" = "b i5 c6" ]'
  cmd_done i5 c5
  check "done with a commit keeps a newer ping pending" 'grep -q "	i5	c6	" "$t/state/queue.tsv"'
  check "ids match by prefix" 'same_id ac94ed2 ac94ed2f00 && same_id ac94ed2f00 ac94ed2 && ! same_id ac94ed2 bc33496'
  cmd_done i5
  check "done without a commit drops every ping for the issue" '! grep -q "	i5	" "$t/state/queue.tsv" && ! grep -q " i5 " "$t/state/delivered"'
  rm -rf "$t"
  return $fail
}

case ${1:-} in
  init) cmd_init ;;
  cosign) shift; cmd_cosign "$@" ;;
  start) cmd_start ;;
  rotate) cmd_rotate ;;
  stop) cmd_stop ;;
  send) shift; cmd_send "$@" ;;
  listen) cmd_listen ;;
  wait) shift; WANT="$*"; cmd_wait ;;
  presence) need_me; name_ok "${2:-}" || die "usage: presence <peer>"; peer_present "$2" ;;
  pending) cmd_pending ;;
  done) shift; cmd_done "$@" ;;
  '') selftest ;;
  *) echo "usage: sideband.sh init | cosign <peer> | start | rotate | stop | send [--when-present] <peer> <issue> | listen | presence <peer> | wait [<issue>...] | pending | done <issue> [<commit>]" >&2; exit 2 ;;
esac
