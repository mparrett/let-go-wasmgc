# lower-wasm inventory (written 2026-10-01 21:00, end of the campaign)

Everything here is on joint `main` (ADR-017: joint does not branch), local
only, never pushed. Skunkworks rule: `AGENTS.md` and memory
`feedback-emit-wasm-is-skunkworks`. Read with: `README.md` (scaffold),
`ORCHESTRATOR-HANDOFF.md` (how the campaign was run), `STATUS.md`,
`DECISIONS.md` D1–D127, `FINDINGS.md`, and the summary at
`docs/project_incoming/letgo-emit-wasm-campaign-summary-2026-10-01.md`.

## Try it first (what Matt will want)

```sh
cd ~/projects-new/3p/joint-xsofy/dev/lower-wasm
# 1. xsofy in the browser from the emitted module, real shell, Playwright-driven
# title + map, prints timings
checks/browser-boot.sh --xsofy
# byte-identical to the stock lane at seed 424242
checks/lane5.sh
# 2. open it yourself: build the serve dir and serve it (no COI needed)
# compiles xsofy main.lg (~80 s) + wasm-opt, cached by content
host/build-xsofy-module.sh /tmp/lw-play/xsofy.wasm
# real xsofy-shell.html + adapter + module
host/build-xsofy-serve.sh /tmp/lw-serve /tmp/lw-play/xsofy.wasm
# adapter's default module name (or pass ?module=xsofy.wasm)
cp /tmp/lw-serve/xsofy.wasm /tmp/lw-serve/module.wasm
# then http://localhost:8260/index.html?seed=424242
python3 -m http.server 8260 -d /tmp/lw-serve
# 2b. play in the terminal instead (node host goes raw on a TTY; --url feeds ?seed=)
node host/node-host.mjs /tmp/lw-play/xsofy.wasm --url seed=424242
# 2c. with the dev console (backtick): os/getenv reads the node process's environment
XSOFY_DEV=1 node host/node-host.mjs /tmp/lw-play/xsofy.wasm --url seed=424242
# 3. legmacs in the browser (round 2, P6.4)
host/build-legmacs-module.sh /tmp/lw-play/legmacs.wasm
host/build-legmacs-serve.sh /tmp/lw-legmacs /tmp/lw-play/legmacs.wasm
cp /tmp/lw-legmacs/legmacs.wasm /tmp/lw-legmacs/module.wasm
python3 -m http.server 8261 -d /tmp/lw-legmacs
# 4. test-drive the evaluator (round 3, P7.5): in *scratch* type a defn, C-x C-e, then a call, C-x C-e
#    (echo area shows => #'legmacs.main/f, then => 42); C-x C-c quits. Same in the browser at :8261.
node host/node-host.mjs /tmp/lw-play/legmacs.wasm
# 5. the let-go REPL page (round 3): build + serve dir, then http://localhost:8262/repl.html
host/build-repl-serve.sh /tmp/lw-repl
python3 -m http.server 8262 -d /tmp/lw-repl
# then open http://localhost:8261/index.html
# 3. a plain program through the backend vs native lg
WASM_RUN=checks/wasm-run.sh checks/oracle.sh corpus/wasm/maps.lg
# 4. the whole board
checks/gate.sh 1 ; checks/gate.sh 2 ; checks/gate.sh 3 ; checks/gate.sh 4
```

The first compile after any `src/` or `rt/` change rebuilds the runtime
library (~90 s, `src/.rtlib/` or `$LW_RTLIB_DIR`); later compiles take 6–15 s.

## Layout

| path | what | owner during the campaign |
|---|---|---|
| `src/lower_wasm.lg` | the backend: IR → WasmGC text; one rec group; intrinsics; closures `$Fn`/`$FnV`; var table; EH; tail calls; purity pins | P1.x, P2.1b, P2.11, P2.12 |
| `src/driver.lg` | file/multi-namespace driver, `-source-paths`, `--test`, var/namespace symbols | P1.0, P3.2, P2.14 |
| `src/lw_rt.lg` | loads `rt/wasm/*.lg` in README order, lg-defined let-go stdlib on demand (core, string, zip, data, set, walk…) from let-go at 4e769212, twins, ext-twins, rtlib cache | P2.1b, P2.14 |
| `src/lw_ext.lg` | backend-owned lg fills: variadic natives, regex engine (RE2 subset), format, json, dot interop, host seams | P2.12, P2.14, P4.1 |
| `src/testshim.lg`, `src/run.mjs` | minimal `test` ns for compiled test files; Node runner (worker, 256 MB stack, imports) | P2.1b, P1.2 |
| `rt/wasm/*.lg` | the runtime in the constrained dialect: intrinsics (43), pvec, seq (owns all boxes + kinds 0–37), phm/phs (array-map/HAMT parity), str (exact Go float format), core, reader (EDN), math, xxhash (canonical XXH3), arrays, host, term, lang; `README.md` has load order and the kind table | P2.x, P3.x, P4.1 |
| `host/` | browser/node/wasmtime host, JSPI sleep + read_key, key coalescing, `ABI.md`, shell adapter, build scripts | P4.0, P4.1 |
| `checks/` | `oracle.sh` (THE match relation), `items.tsv` (definition of done per row), `run.sh`/`gate.sh`, `run-corpus.sh`, `run-tests.sh`, `census.sh`, `world-parity.sh`, `lane5.sh`, `browser-boot.sh`, `hash-parity.sh`+`wasm-hash.sh`, `native-twins.sh`, `sem.sh`, `affected.sh`, `bench-fib.sh` | all |
| `corpus/` | every oracle as files: scalar, opmatrix, typed, control, closure, review, review2 (fuzz), wasm (14 programs + pending/), intrinsics (native tests), hash, maporder, natives, edn, floats, census, depth, host, xsofy (repros + size-boot), examples, seqs, core-tests | all |
| `tools/` | native inventory, twin manifest, reach wrapper | P2.8 |

## Knobs (all optional)

`LG` (native lg, default `~/projects-new/3p/lg-bin/lg-4e76921230`), `LG_ARGS`
(e.g. `-source-paths …`, oracle passes it to both sides), `WASM_RUN`,
`LW_PAR` (corpus 3 / native tier 4), `LW_GATE_J` (2), `CENSUS_SHARDS` (4),
`FRESH=1` (census), `LW_SLOTS` (4) + `LW_SEM`, `LW_RTLIB_DIR`, `LW_RT_DIR`
(overlay an rt/ copy to test a patch), `LW_MODULE_CACHE`, `SLOW=1` (native
tier full), `KEEP=1` (keep temp dirs), `LW_SETTLE`/`LW_MIN_MS` (lane 5).

## Things that bit us (keep)

- A `coverage/` directory anywhere is hidden by the global gitignore; we use `census/`.
- lg at main is required (`just lg-at 4e769212`); the `smoke: boot budget` step is flaky cold, rerun.
- `oracle.sh`: lg prints its error REPORT to stdout with ANSI; on failure the oracle compares the normalised first error line, not bytes. MATCH when both sides fail identically is possible (check line counts on a new program).
- `.expected` files are snapshots checked BEFORE the oracle (STALE-EXPECTED); `oracle.sh` never reads them. `SKIP` files take `# reason` comments.
- Committing while an agent edits `src/` can capture half a change: the backend REFUSES to load an rt intrinsic without an emitter (coupled changes land together; see f64-neg, D108).
- let-go's `examples/server.lg` and `mandelbrot.lg` hang/run for minutes natively: the examples corpus SKIPs them.
- The stock-Go lane drops/merges keys under load; lane 5 is settle-based (D119).
- Timings in this tree were taken at load 5–45; byte-identity results are the signal, times are soft.
- `LW_MODULE_CACHE` once produced two keys for identical inputs (unexplained; costs a recompile).
- The native tier is budgeted 120 s at load ≤ 10 (D81); do not trim tests to meet it.

## Known gaps (named limits, all recorded in DECISIONS/FINDINGS)

Ratio/BigInt/BigDecimal (D15); `defprotocol`/`deftype`/go blocks/`future`
(Phase 5); dynamic `binding` of user vars only via the var table, `*out*`
lexical; `with-meta` on a variadic fn drops the variadic arity; identity hash
of atoms/fns per kind; printing a fn refused; `sort` incomparable-pair message
may name a different pair; `slurp`/`open`/host file I/O; `sorted-map`/`sorted-set`;
`to-array`; regex outside the RE2 subset; `*ns*` rebinding.

## What is NOT here

Nothing was pushed, no PR/issue was opened, the let-go/xsofy checkouts were
never modified. The upstream-worthy findings are collected, generically
phrased, in `docs/project_incoming/letgo-upstream-findings-from-lower-wasm-2026-10-01.md`.
