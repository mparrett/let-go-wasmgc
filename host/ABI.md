# lower-wasm host ABI (P4.0, proposed as D88)

Each lower-wasm module talks to its host only through the imports and exports
listed here. `lg-wasm-host.js` implements them for browsers and Node,
`node-host.mjs` wraps it for the command line, and `wasmtime-adapter.wat`
implements the same set on WASI preview1 for wasmtime (which has no
`emit`/`url_param`/`argc`/`arg`: it runs only the P4.0 smoke modules). As of
2026-10-01 (P4.1-backend) the backend emits every import marked "emitted",
each only when the program reaches it (imports are tree-shaken); `getenv` is
still "defined".

## Exports (module side)

| export | type | meaning |
|---|---|---|
| start function (`_rt_init`) | — | builds runtime globals during instantiation; must not block |
| `lw main` | `() -> anyref` | runs the program's top-level forms; the host calls it once, through `WebAssembly.promising` when JSPI is present |
| `lw mem` | memory | linear memory, owned by the module (D5: strings are GC byte arrays; linear memory is only the copy area for crossing the boundary) |
| `lw lgex` | tag | the lg exception tag; an uncaught lg throw leaves `lw main` as this |
| `lw report` | `(eqref) -> ()` | formats an uncaught exception value through `print_*` |
| `lw trap` | `() -> i32` | 1 if a `wasm/trap` set a message (it prints it), else 0 |

Export names contain a space so no lg symbol can collide with them (P1.7 bug-09).

## Imports

"Suspends" means the import is a `WebAssembly.Suspending` in JS hosts: the
wasm stack parks until the returned Promise settles, and the JS event loop
keeps running in the meantime. wasmtime has no JSPI, so there these imports
simply block the thread.

| import | signature | suspends | status | semantics |
|---|---|---|---|---|
| `env.print_i64` | `(i64) -> ()` | no | emitted | decimal text of the value to the current output fd |
| `env.print_str` | `(ptr i32, len i32) -> ()` | no | emitted | UTF-8 bytes `[ptr, ptr+len)` to the current output fd |
| `env.print_nl` | `() -> ()` | no | emitted | `"\n"` to the current output fd |
| `env.write` | `(fd i32, ptr i32, len i32) -> i32` | no | emitted | bytes to fd 1 (program stdout) or fd 2 (stderr); returns `len`. The runtime copies the bytes to address 32 first (`rt_host_write`) |
| `env.sleep` | `(ms i64) -> ()` | **yes** | emitted | resumes after `ms` milliseconds (`setTimeout`); `ms <= 0` resumes on the next macrotask. Reached from `(<!! (timeout ms))` via `wasm.host/take!!` (D6, D87) |
| `env.nanotime` | `() -> i64` | no | emitted | monotonic ns (`performance.now()*1e6` in JS hosts, `CLOCK_MONOTONIC` under WASI); only differences mean anything |
| `env.getenv` | `(name_ptr i32, name_len i32, buf i32, cap i32) -> i32` | no | emitted (2026-10-02) | `os/getenv`: copies the value into `[buf, buf+cap)` and returns its byte length; returns `> cap` (nothing copied, retry with a bigger buffer) or `-1` when unset (the runtime reads unset as `""`, as os.Getenv does). The browser host's env is `{}`; node-host passes `process.env` (plus `--env K=V`), so `XSOFY_DEV=1` reaches xsofy's `dev?` there |
| `env.emit` | `(name_ptr i32, name_len i32, json_ptr i32, json_len i32) -> ()` | no | emitted (P4.1) | `js/emit`: the event name and the data as JSON text, let-go's `_lgEmit(name, dataJson)` shape; the JSON is byte-identical to let-go's (`fromValue` + `encoding/json`: sorted keys, HTML escaping). The browser host parses the JSON and fires the `window` CustomEvent the shell listens for (`xsofy/startup` sets the title and quest, `xsofy/stats`, `xsofy/replay-dump`, …); node and run.mjs drop it. xsofy calls `js/emit` 10 times |
| `env.url_param` | `(name_ptr i32, name_len i32, buf i32, cap i32) -> i32` | no | emitted (P4.1) | `js/url-param`: getenv's contract over the page's query string; `-1` when absent or off-browser (native returns nil). xsofy reads `?seed=` and friends through it (6 calls) |
| `env.argc` | `() -> i32` | no | emitted (P3.2, D115) | `os/args` length; JS hosts take `argv` (default `['lg']`) |
| `env.arg` | `(i i32, buf i32, cap i32) -> i32` | no | emitted (P3.2, D115) | argument `i`, getenv's copy contract |
| `term.read_key` | `(buf i32, cap i32) -> i32` | **yes** | emitted (D104) | waits for the next key and copies its UTF-8 bytes (one `sendInput` call = one key, ≤ 16 bytes, as in let-go's SAB ring) into `[buf, buf+cap)`; returns the byte count, **0 = end of input** (`read-key` → nil). Coalesces (D98, below). The runtime builds the lg String |
| `term.key_pending` | `() -> i32` | no | emitted (D104) | 1 if a key is queued, else 0 (`key-pending?`) |
| `term.size` | `() -> (i32 i32)` | no | emitted (D104) | `cols rows` as a multi-value result (`term/size` → `[cols rows]`); default 80×24 |
| `term.write` | `(ptr i32, len i32) -> i32` | no | defined | same stream as `env.write` fd 1. let-go's `term/write` is `(write *out* s)`, so the runtime may use either; this exists so a terminal host can tell term output apart if it ever needs to |

**Not imports, and why:**
- **Colour and cursor** (`term/set-fg`, `set-bg`, `move-cursor`, `clear`, `bold`, …):
  let-go's wasm build already writes these as ANSI escapes to `*out*`
  (`pkg/rt/term_wasm.go`, `WriteToOut`), and xterm interprets them. They belong
  in the runtime as string builders over `env.write`. `xsofy-shell.html` takes
  nothing from `LetGoHost` beyond the text stream.
- **`set_size`** goes from host to module, so it is not an import. It is
  `LetGoHost.setSize(c, r)` → `host.setSize`, which updates the state that
  `term.size` reads.
- **`term/flush`**: `env.write` is unbuffered on every host, so the runtime can
  implement flush as a no-op.

## Who owns what

- **Module:** linear memory and everything in it. Address 0 holds an active
  data segment (`"niltruefalse…"`) that `print_str` reads, so low addresses are
  **not** free scratch (the first wasmtime adapter assumed they were and
  garbled `true`). Strings bound for `env.write` are copied to 32 and up.
- **Host:** reads `[ptr, ptr+len)` synchronously inside the call and copies it
  out (the module reuses the area right away). For `read_key` the host writes
  into `buf` **after** resuming, so it re-reads `mem.buffer`, since memory may
  have grown while the stack was parked. Text decoding is per fd and streaming
  (`TextDecoder {stream:true}`), so a UTF-8 sequence split across two writes
  still decodes.
- **Input queue:** belongs to the host. Keys sent before `lw main` starts are
  dropped, and at most 8 keys queue (the rest are dropped). Both match let-go's
  ring; `node-host` lifts the cap for piped input.

## Key coalescing (D98)

`term.read_key` is the consumer half of let-go's `HostKeySource.ReadKey`
(`pkg/rt/keysource_js_wasm.go:78-127`), and `sendInput` the producer half
(`lg-host-core.js` `_lgKey`):

- `sendInput` refuses an empty key, a key over 16 UTF-8 bytes, and a key past
  the 8-slot capacity (returns `false`, as `_lgKey` does).
- `read_key` takes the head key. If its length is outside 1..16 it is drained
  alone and the read returns 0 (nil). Otherwise every following queued key
  with the same bytes is drained with it: a held key that outruns the program
  is one read, not a backlog. Distinct keys are never merged.
- `sendInput` always queues and then wakes a parked `read_key`, which resumes
  in a later microtask and reads the queue itself. Keys sent in one task (an
  auto-repeat burst) are therefore all queued by the time it looks, which is
  what makes them coalesce even when the program was already waiting. Handing
  the first key straight to the waiter, as P4.0 did, would make a burst into
  two reads.

`node-host` turns coalescing **off** unless given `--coalesce`, so scripted
and piped input still reaches the program key for key. The wasmtime adapter
reads stdin and does not coalesce (it has no queue to look ahead in).

## Errors (identical to src/run.mjs, D12)

If `lw main` rejects, the host switches the current output fd to 2 and prints
`error: `. If the exception carries `lw lgex`, `lw report(arg0)` prints the
message. Otherwise, if `lw trap()` is 1, the module has already printed it.
Failing both, the host prints the JS error message. A newline follows, and the
result is `{code: 1, error: <that line>}`. A trap in the start function
surfaces from `instantiate` and gets the same `error:` line. node-host matches
run.mjs byte for byte on `corpus/control/uncaught{,-value,-raw}.lg`. Under
wasmtime an uncaught lg exception exits 1 with wasmtime's "thrown Wasm
exception" backtrace instead; the adapter does not format it.

## Browser surface: `window.LetGoHost`

`index.html` defines let-go's surface with the same shape as
`lg-host-core.js`: `onReady(cb)`, `onOutput(cb)`, `onEmit(cb)`,
`sendInput(str)`, `setSize(c, r)`. It is a classic script that runs before any
shell code and buffers output and the ready signal until a shell registers.
`index.html` reports ready mode **`'jspi'`**. `xsofy-shell-adapter.js`, the
surface the real shell runs on, reports **`'worker'`** (D90). The reason is
the shell's own gate: `xsofy-shell.html` calls `setSize`, registers
`term.onResize` and wires `term.onData` → `sendInput` only inside
`if (mode === 'worker')`. In `'main'` (let-go's output-only mode) and in any
other value it shows output but never sends a key or a size. `'worker'` names
let-go's worker + SAB-ring mechanism, which this host does not use; what the
shell actually needs to know is "input is live", and that is true here.
Reporting `'worker'` keeps the shell byte-identical to upstream (changing its
gate would be an xsofy PR). With `'jspi'` the `--xsofy-shell` check fails
boot, size, held and quit (falsified 2026-10-01).

## xsofy-shell.html on this host (P4.1)

`host/build-xsofy-serve.sh <dir> [modules…]` builds a serve directory:
`host/xsofy.html` (let-go's `-w-shell none` frame: `#status`, `#app`, then a
classic `<script src="xsofy-shell-adapter.js">`) with the shell injected by
the workspace's own `local-scripts/inject-shell.sh` (sentinel-wrapped, before
the body close tag; the shell is copied byte for byte). The adapter defines
`window.LetGoHost` synchronously, so it exists when the shell binds at parse
time, then dynamic-imports `lg-wasm-host.js`.

What the shell expects at boot, and who provides it:

| shell expects | provided by |
|---|---|
| `window.LetGoHost` with `onReady/onOutput/sendInput/setSize` before its own script runs | adapter (classic script ahead of the injection point) |
| `#app` (xterm mount) and optionally `#status` (hidden on ready) | `xsofy.html`, same ids as let-go's `host.html` |
| `onReady(mode)` with `mode === 'worker'` to wire input and size | adapter reports `'worker'` (above) |
| output buffered until it registers `onOutput` | adapter buffers; the shell buffers again until xterm opens |
| xterm 5.5 + addon-fit from cdn.jsdelivr.net | network; nothing local |
| Fairfax HD (inlined base64 in the shell), loaded before `term.open` | the shell itself; `?font=system` skips it |
| `build-info.json` next to the page (optional; 404 = ad-hoc bundle) | absent |
| `xsofy/startup`, `xsofy/stats`, `xsofy/term-size`, `xsofy/perf`, `xsofy/replay-dump` window events (title, quest, stats, replay link) | `env.emit` → `onEmit` default → `CustomEvent` (P4.1: the emitted xsofy fires them) |
| nothing printed at boot: the title bar shows `—` until `xsofy/startup` arrives; the terminal shows whatever the program writes | — |

The adapter starts `lw main` only after the shell's first `setSize` (or 2 s
without one). The shell calls `setSize` after awaiting its font and opening
xterm, roughly 150–180 ms after load in headless Chromium; a module that
starts sooner reads the 80×24 default instead of the real grid. let-go's lane
has the same race but hides it behind its slower boot.

## COI: not needed

let-go's `read-key` needs a SharedArrayBuffer ring, hence COOP/COEP (the
workspace CLAUDE.md, "Serving a WASM bundle requires cross-origin isolation").
With JSPI, a blocked `read_key` is a parked wasm stack waiting on a Promise
that `sendInput` resolves on the same thread, so no shared memory is involved.
Evidence from `checks/browser-boot.sh` (Chromium 148, 2026-10-01): served by
plain `python3 -m http.server`, the page reports `crossOriginIsolated=false`
and `SharedArrayBuffer` undefined, yet hello still matches native lg and the
keys probe echoes `a b q`. Served by `coi-serve.py`, both are true and the
results are identical. The JSPI lane can therefore deploy without the COI
service-worker fallback. That fallback is also unreliable under headless
automation (CLAUDE.md), so dropping it simplifies P4.1–P4.3.

## Stack depth under JSPI (a P4.1 risk)

Closed by D99: xsofy's deepest stack is 20 lg frames, well inside the
browser budget measured below.

A promising export runs on a V8 secondary stack sized by
`--wasm-stack-switching-stack-size`, 984 kB by default. A worker's
`resourceLimits.stackSizeMb` (run.mjs's D33 mechanism) does not reach that
stack. Measured with a non-tail boxed `(+ 1 (down (- n 1)))`:

| host | deepest passing | first failing |
|---|---|---|
| Chromium 148, page (flags impossible) | 5,000 | 7,000 |
| node 25, defaults or in a worker with 256 MB | 5,000 | 10,000 |
| node 25 main thread, `--stack-size=262000 --wasm-stack-switching-stack-size=262144` | 1,000,000 | — (3M fails, as it does under run.mjs) |
| wasmtime 47, `-W max-wasm-stack=268435456` | 1,000,000 | — |

So node-host runs on the main thread and re-execs itself with those two
flags. In a browser the limit is fixed at about 5–7k frames of this shape.
Native lg grows its stacks into the millions. Before P4.1, check whether
xsofy's deepest recursion (map generation, FOV) fits. If it does not, the
fix belongs in the backend (loops for self-recursion, or an explicit stack),
not in the host.
