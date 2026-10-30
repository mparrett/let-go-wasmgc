# checks/sideband

Attention pings between two owners' agents (git-issue:ac94ed2). A ping says
"sync and read this issue": `<git-issue id> <tip of refs/notes/issue-<id>>`,
SSH-signed, put on the recipient's topic on the public OpenDHT network. It only
shortens the wait for the next notes sync; the hourly poll stays the floor, and
nothing an agent does depends on a ping arriving.

Rules, both sides:

- A ping names an issue that exists and is open. It never opens a topic: a new
  subject goes to the tracker as an issue first.
- A ping prompts a fetch and a read, never an action.
- At most two pending issues per peer; the rest are dropped and logged.
- Each side logs what it sends and receives (`$LW_SIDEBAND_STATE`).
- Either owner stops the channel by removing a co-signature by PR, or by
  stopping the listener.

## Keys

Three Ed25519 keys per owner, after Google's LOAS: a human-held root, an
unattended issuer, and short-lived credentials it mints.

| key | where | used by |
|---|---|---|
| co-signing | OS key store, trusting no program: every use asks the owner | `cosign`, by hand |
| issuer | OS key store, read once at `start` into a private `ssh-agent` | `rotate`, unattended |
| ping | that agent only, with a certificate for `LW_SIDEBAND_TTL` (20h) | `send` |

The key store is the macOS Keychain, or libsecret's `secret-tool` on Linux. No
agent can co-sign: the co-signing key never enters the agent, and its Keychain
item prompts on every read. libsecret has no per-read prompt, so it can hold an
issuer key but not a co-signing key; `init` refuses there until Linux has a
backend that asks on each use. A headless Linux host has no libsecret keyring
and would need another backend, such as the kernel keyring (`keyctl`).

The listener checks the signature and the payload's shape, not whether the
issue is open: the peer's notes may not have synced yet. Whatever reads
`pending` checks the issue with `git issue show` before reading it.

Committed here, public halves and signatures only:

| file | what |
|---|---|
| `keys/<owner>-cosign.pub` | the owner's co-signing key |
| `keys/<owner>-issuer.pub` | the owner's issuer key |
| `keys/<peer>-issuer.by-<owner>.sig` | the owner's co-signature over the peer's issuer key |

A ping from `<peer>` is accepted only when its key holds a current certificate
from `<peer>`'s issuer key, for principal `<peer>` and the `lw-sideband`
namespace, and the recipient's own co-signing key has signed that issuer key.
A lapsed ping certificate is rejected; `send` rotates to a fresh one.

## Onboarding

1. `LW_SIDEBAND_OWNER=<you> checks/sideband/sideband.sh init`, then commit
   `keys/<you>-cosign.pub` and `keys/<you>-issuer.pub` by PR.
2. Once both owners' keys are merged, each runs `sideband.sh cosign <peer>`
   (it asks for the key store's approval) and commits
   `keys/<peer>-issuer.by-<you>.sig` by PR. At the Keychain prompt, click
   Allow, never Always Allow: Always Allow adds `security` to the item's
   access list, and from then on any of your processes reads the co-signing
   key without asking. `security dump-keychain -a` shows an access list that
   has grown.
3. At launch: `sideband.sh start`, then `sideband.sh listen`. From then on,
   `send <peer> <issue>`, `pending` and `done <issue>` run unattended.
   `send` refuses until the issue's note is on the remote, since the peer
   fetches it from there.
   `sideband.sh stop` ends the agent, and the issuer and ping keys with it.

## Waking a session

A ping matters between the points where a session would fetch anyway, such
as each prompt. A session working on an issue runs, as a background command:

    checks/sideband/sideband.sh wait <issue>...

A pending ping is the token: `wait` blocks while none for those issues (any
issue, given none) is queued, then prints `<peer> <issue> <notes commit>` and
exits, which wakes the session. The listener has already fetched the note
into `refs/issue-watch/issue-<id>`, where the prompt hook reads it, so the
woken session reads the issue at once, runs `done <issue> <commit>`, and
starts `wait` again. A ping that lands meanwhile stays queued, so the next
`wait` returns at once. `wait` returns each ping once: one a session ignores
without `done` stays in `pending` but does not wake it again. Issue ids match by prefix, so a short and a full id
name the same issue.

`sideband.sh` with no arguments is the offline self-test (row P0.8): a
throwaway key store, co-signing both ways, accepted and rejected pings
(tampered, wrong payload, unco-signed issuer, lapsed certificate), the
queue bound, and `wait`.
