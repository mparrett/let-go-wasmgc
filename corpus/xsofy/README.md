# corpus/xsofy — P3.2: xsofy's world through the backend

`checks/world-parity.sh [--keys wait|autoex|descend|deep|<str>] [N] [turns]`
compiles `corpus/dump-world.lg` once (xsofy on `-source-paths`, read from
`LG_ARGS` by `checks/wasm-run.sh`) and compares its dump with native lg per
seed through `checks/oracle.sh`. Results as of 2026-10-01 (lg 4e769212, xsofy
0c38395):

| run | result |
|---|---|
| 20 seeds × 60 turns, wait | 20/20 MATCH |
| 5 seeds × 200 turns, autoex (`x` then waits) | 5/5 MATCH |
| 5 seeds × 200 turns, descend (`>` then waits) | 5/5 MATCH |
| seeds 7, 9, 10 × 200 turns, deep (98 × `x`, then `>`) | 3/3 MATCH, all reach floor 2 |

measure.lg's autoex and descend fixtures never leave floor 1 (`>` only routes
to stairs already in `:memory`, and with waits after it nothing walks there),
so `deep` is the fixture that covers `change-floor` and a second floor.
Autoexplore kills the player on every seed 1–5 before turn 200, so death is
covered too.

## Root causes found (each has a repro here; native output in its header)

| repro | cause | fixed in |
|---|---|---|
| repro-01 | `term/size` is nil off a TTY natively; run.mjs said 80×24, so each descend drew the title card (ANSI) on stdout | run.mjs reports (-1,-1) = no terminal; `lw-ext/term-size-v` |
| repro-02 | a library def's Var is bound at compile time; lg's `vector?`/`string?` see through a Var, so the `:def` target looked like a vector literal | `typed-aux?`, `template?`, `string-const?`, `symbol-const?` exclude Vars |
| repro-02 | `^:private` reads as a `(with-meta name ..)` def name, which ir.build evaluates | driver drops the name's meta for library defs |
| repro-02 | `binding` of a program dynamic var (xsofy.opcontext/*op-context*) | saved/restored var-table global (`push-var!`/`pop-var!`) |
| repro-04 | typeinfer's self-call test matches by name: string/ends-with? → core/ends-with? was typed :int | `self-call?` false on a same-named foreign call (UPSTREAM) |
| repro-05 | unbound natives on the path: core/long, ints, re-find, string/join and ends-with? (string.lg is lg code), *assert*, *out*/*err*, push-binding!, let-go.core/now (trapped at ui load) | lw_ext fills, string.lg compiled like core.lg, var constants |
| repro-06 | os/args was nil, so the dump ignored its seed | `env.argc`/`env.arg` imports (proposed) |
| (census) | `validate after licm` on bfs-path (reached by descend) | rebuild without licm on that error (UPSTREAM) |

## P4: xsofy's real entry in the browser (2026-10-01)

`host/build-xsofy-module.sh` compiles `main.lg` itself (`-source-paths` =
xsofy, D114), wasm-opt -O3, cached by content. Checks:

| check | what |
|---|---|
| `checks/browser-boot.sh --xsofy` | term-demo.lg under node-host == native lg on a 100x30 pty; the module in the real shell reaches the title card and the map, ?seed= honoured, xsofy/startup + xsofy/stats received |
| `checks/lane5.sh` | settle-based probe walk (`browser-boot.mjs --settle-walk`: `zz-determinism-probe.mjs`'s `l l j j h k l j` at seed 424242, each key sent after the previous turn finished): `document.body.innerText` byte-identical to the stock-Go lane (`lg -w` at 4e769212 + the same injected shell). The held-key burst walk is printed too but is informational only |
| `checks/size-boot.sh` | bundle bytes and boot times vs the stock and TinyGo lanes, written to `size-boot.md` |

Lane 5's gate is settle-based because fixed spacing is load-dependent: the original probe sent a key every 400 ms, and under load 15-45 whether a key landed mid-turn changed the dump from run to run (one run probe IDENTICAL / held DIFFER, the next the reverse). The stock-Go lane is the sensitive one (its turns took 200-2000 ms at that load, the emitted lane 30-180 ms); both lanes coalesce identical queued keys (D98), so a late `l` after `l` is merged into one step. Measured 2026-10-01 at load 17-22: the 400 ms walk gave the stock lane a final turn counter of 5-8 for the same 8 keys (4 of 5 runs differed from the emitted lane, which always reached 8). The settle walk sends a key only after the game's `xsofy/stats` event for the previous one and 3 x 100 ms of unchanged xterm rows (>= 200 ms; a wait over 5 s is a harness failure, exit 2, not a lane mismatch), and logs the turn counter per key. The held-key bursts coalesce by design, depend on timing in both lanes, and so cannot be a byte-identity gate; `lane5.sh` prints them as informational, and the deterministic property (a burst is ONE read) stays gated by `checks/browser-boot.sh`'s `held` assertion.

| repro | cause | fixed in |
|---|---|---|
| repro-07 | n-ary `dissoc` (4 keys) fell through to `$rt_invoke5`: FATAL ERROR on the first map frame | `seq-variant-table` → `lw-ext/dissoc-n` |
| repro-08 | `(.Sub (now) epoch)` (ui/millis): `core/.` was a nil slot, the title card's first tick died | `lw-ext/dot-v` (Int `Sub`; other interop a named error) |
| repro-09 | `os/os-name` unbound; the wasm lane says "js" (by design differs from native "darwin") | `lw-ext/os-name-v` |
| repro-10 | `core/char?` unbound (reached through `long-v`) | `lw-ext/char-v` |
| repro-11 | `js/emit` / `js/url-param` never reached the host: no title bar, ?seed= ignored | `host-emit` / `host-url-param` intrinsics (`env.emit`, `env.url_param`, D100), `json-str` |

`js/emit`/`js/url-param` are routed to `src/lw_ext.lg` only while
`rt/wasm/host.lg` lacks `host-emit`; `rt-host-emit.patch` here moves the two
intrinsics and the JSON encoder (runtime dialect) into `wasm.host`, after
which lw_rt stops routing and the runtime twins are used as they are.
