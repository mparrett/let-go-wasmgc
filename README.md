# let-go-wasmgc

An experimental backend for [let-go](https://github.com/nooga/let-go), a
Clojure dialect, that compiles let-go's optimizer IR to WebAssembly GC
(WasmGC). A program becomes one wasm module whose functions are real wasm
functions over GC structs, with the let-go runtime it needs compiled in.
The runtime is itself written in let-go (`rt/wasm/*.lg`) and goes through
the same backend. A closure-compiling evaluator in that runtime gives
compiled programs a working `eval`.

This is an experiment, not part of let-go. Stock `lg -w` builds a wasm
module that runs let-go's bytecode VM inside wasm; this backend does not use
the VM at all. Every result here is measured against native `lg` by a
differential check (see "Checks"), and the design record is
[DECISIONS.md](DECISIONS.md), numbered D10 to D169.

## Status (as of 2026-10-02)

- **xsofy** (a roguelike) is playable from the emitted module in the browser
  and in a terminal under node. Its world dumps for seeds 1 to 20 at 60 turns
  are byte-identical to native lg, and a scripted screen dump matches the
  stock build at seed 424242.
- **legmacs** (an Emacs-like editor) boots in the browser and under node.
  316 of its 373 deftests pass under the backend, and 28 of its 30 eval
  tests pass with the in-module evaluator. Typing a `defn` into `*scratch*`
  and evaluating it with `C-x C-e` works.
- **let-go's own core tests**: 271 of the 273 selected deftests pass, with
  the two remaining ones skipped by name.
- **A browser REPL page** (`host/repl.html`) runs a let-go REPL entirely in
  the module.
- **Live demos**: https://matt.parrett.us/let-go-wasmgc/ (REPL, xsofy,
  legmacs; needs Chrome 137 or newer). Built by `host/build-pages.sh` and
  served from the `gh-pages` branch. [docs/READING-GUIDE.md](docs/READING-GUIDE.md)
  is a guided walk through the code.
- Gates 1 to 7 passed on 2026-10-02 with `LW_ATTEST=0`; gate 7 was rerun
  green the same evening after the evaluator's core table gained bit ops,
  `Math/*` and clocks (D169, D170).

Module sizes after `wasm-opt -O3`, brotli-compressed, as of 2026-10-02:

| module | brotli |
|---|---|
| legmacs, with the evaluator | 166 KB |
| legmacs, `LW_NO_EVAL=1` | 120 KB |
| xsofy | 115 KB |
| REPL page module | 77 KB |

Browsers: the hosts need WebAssembly JSPI. As of 2026-10-03 that is Chrome and
Edge 137 or newer on desktop; Safari 27 ships it (iOS included) and Firefox
plans it for 153, so the gap closes on its own. Binaryen's Asyncify cannot
stand in, because it spills locals to linear memory and these modules hold
GC references in locals (`wasm-opt --asyncify` asserts on them).

Named limits, as of 2026-10-02: Ratio and BigInt results are named errors
(D15); `go` blocks and channels are not supported, and `future` runs its
body at the call (D162); the evaluator has no interop, `deftype`,
`defprotocol` or `defmulti` (D160). As of 2026-10-07 a library namespace
(one under `-source-paths`) may define `deftype`, `defrecord` and
`defprotocol`: a type is a keyword tag or a map carrying one, a protocol
method one dispatching defn (D204); `extend-type`, `reify` and `defmulti`
are not seen. [FINDINGS.md](FINDINGS.md) lists native
let-go behaviours we met along the way.

As of 2026-10-03, `--target linear` (or `LW_TARGET=linear`) selects an
experimental linear-memory module with a leaking allocator; WasmGC remains
the default. Run it with `checks/wasm-run-linear.sh`. The Go host uses
[nooga/wazero](https://github.com/nooga/wazero) pinned at
`v1.12.1-0.20260911172836-0ec6142ae8c7`, with
`experimental.CoreFeaturesTailCall` and
`experimental.CoreFeaturesExceptionHandling` enabled and GC disabled.
Milestone corpus results and named refusals are recorded in STATUS.md.

## Prerequisites

The checks and build scripts find their inputs under one root, `LW_ROOT`,
resolved by `checks/env.sh`: it is the directory holding `let-go/`,
`xsofy/`, `legmacs/` and `lg-bin/`. It is found automatically when this
repository is cloned beside those checkouts; otherwise set `LW_ROOT`, or
override the individual paths (`LG`, `LETGO`, `XSOFY`, `LEGMACS`).

- **Go 1.25 or newer** for the linear runner (2026-10-03).
- **Native lg built from let-go commit e9789b7d**, at
  `$LW_ROOT/lg-bin/lg-e9789b7d53` or wherever `LG` points. The driver runs
  under this lg and uses let-go's IR passes from it.
- **A let-go git checkout** (`$LETGO`, default `$LW_ROOT/let-go`) that
  contains commit e9789b7d: `src/lw_rt.lg` reads let-go's `pkg/rt/core/*.lg`
  at that commit with `git show`, and fails with a message naming the path
  when it cannot.
- **wasm-tools** on `PATH` (WAT to binary).
- **binaryen's wasm-opt** (and `wasm-merge` for `checks/browser-boot.sh`):
  the Homebrew install when present, otherwise the one on `PATH`; set
  `WASM_OPT` / `WASM_MERGE` to choose another. Used by the module build
  scripts in `host/`. `LW_NO_OPT=1` skips it.
- **brotli**, for the size lines the build scripts print.
- **node** with WasmGC, wasm exception handling and JSPI. We develop on
  node 25. `src/run.mjs` and `host/node-host.mjs` set their own stack sizes.
- **Chromium through Playwright** for the browser checks
  (`checks/browser-boot.sh`, `checks/repl-page-check.mjs`). These currently
  accept `LW_BROWSER_TOOLS` naming the external `local-scripts` directory
  containing `browser-smoke-playwright/`, `coi-serve.py` and `inject-shell.sh`
  (2026-10-03).
  The default remains `../../../local-scripts` relative to `checks/`.
  Standalone checkouts must configure their installed tools directory.
- **xsofy and legmacs checkouts** (`$XSOFY`, `$LEGMACS`) for those corpora.
  Multi-namespace programs name their source roots through `LG_ARGS`, as
  row P7.3 in `checks/items.tsv` does:
  `env LG_ARGS="-source-paths $LW_ROOT/legmacs" checks/run-corpus.sh corpus/eval-buffer`.

Environment variables that matter:

| variable | effect |
|---|---|
| `LW_BROWSER_TOOLS` | external browser-tools directory for Playwright, COI serving, shell injection and boot probes (2026-10-03) |
| `LW_ROOT` | the root holding `let-go/`, `xsofy/`, `legmacs/`, `lg-bin/` (`checks/env.sh`) |
| `LG` | native lg used by the driver and as the oracle's reference |
| `LG_ARGS` | args passed to native lg before the program; its `-source-paths` also names the backend's library roots |
| `LW_NO_EVAL=1` | build without the evaluator and the program table (D163) |
| `LW_PROGRAM_TABLE=1` | install the program table for a program that reaches the registry without `eval` (a library init that resolves or interns its own vars: let-go's `ir.data`), D204 |
| `LW_EXPORT_RT=1` | export every runtime function as `lw rt <id>` and the var slots, for code compiled at run time (D193) |
| `LW_RUNTIME_COMPILE=1` | load the emitter into the runtime; with `LW_EXPORT_RT=1` the module exports `lw compile` and `lw eval` (D193) |
| `LW_NO_OPT=1` | skip wasm-opt in the module build scripts in `host/` |
| `LW_MODULE_CACHE=<dir>` | `checks/wasm-run.sh` reuses the compiled module of an unchanged program |
| `LW_RTLIB_DIR=<abs dir>` | where the compiled runtime library is cached (default `src/.rtlib`) |
| `LW_ATTEST=0` | make `checks/gate.sh` rerun every row instead of skipping attested ones |
| `XSOFY_DEV=1` | read by xsofy through `os/getenv`; under `host/node-host.mjs` it opens xsofy's dev console |
| `LETGO`, `XSOFY`, `LEGMACS` | the three checkouts; default `$LW_ROOT/<name>` |

## Quick start

Run from the repo root. The first compile after any change to `src/` or
`rt/` builds the runtime library, which took about 90 s as of 2026-10-02;
later compiles reuse it.

Compile and run one program under node:

```sh
checks/wasm-run.sh corpus/scalar/fib.clj
```

Compare it against native lg (prints `MATCH` or `MISMATCH <what>`):

```sh
WASM_RUN=checks/wasm-run.sh checks/oracle.sh corpus/scalar/fib.clj
```

Run a gate (here phase 1), rerunning every row:

```sh
LW_ATTEST=0 checks/gate.sh 1
```

Build and serve the REPL page, then open http://localhost:8262/repl.html.
JSPI needs no cross-origin isolation headers (D91), so a plain static server
works:

```sh
host/build-repl-serve.sh /tmp/lw-repl
python3 -m http.server 8262 -d /tmp/lw-repl
```

Build and serve the eval/compile explorer, then open
http://localhost:8263/explorer.html. Type let-go forms; the page shows what
the module's evaluator returns and what the module's emitter compiles them
to, linked into the running module and run, with an agree indicator and the
compiled module's size, sections and bytes (D194). The first build of its
compiler host takes a few minutes and is cached:

```sh
host/build-explorer-serve.sh /tmp/lw-explorer
python3 -m http.server 8263 -d /tmp/lw-explorer
```

Play xsofy in a terminal, with its dev console enabled (backtick opens it):

```sh
mkdir -p /tmp/lw-play
host/build-xsofy-module.sh /tmp/lw-play/xsofy.wasm
XSOFY_DEV=1 node host/node-host.mjs /tmp/lw-play/xsofy.wasm --url seed=424242
```

Run legmacs in a terminal (`C-x C-e` evaluates, `C-x C-c` quits):

```sh
host/build-legmacs-module.sh /tmp/lw-play/legmacs.wasm
node host/node-host.mjs /tmp/lw-play/legmacs.wasm
```

## Layout

- `src/` the compiler
  - `src/driver.lg` reads a program, evaluates its defns in-process so let-go's
    IR builder resolves vars, runs the IR pipeline per defn and writes one
    WAT module. Usage: `lg -source-paths src src/driver.lg <prog.lg> <out.wat>`.
  - `src/lower_wasm.lg` walks the structured IR control tree and emits WasmGC
    text: values, closures, the var table, exception handling, tail calls.
  - `src/lw_rt.lg` loads `rt/wasm/*.lg` in load order, indexes its types, defns
    and twins, and caches the compiled runtime library.
  - `src/lw_ext.lg` let-go code the backend compiles for natives the runtime has
    no form for (variadic uses, a regex engine, format, JSON).
  - `src/run.mjs` runs a module like `lg` runs a program: stdout, exit status,
    `error: <message>` on an uncaught exception.
  - `src/testshim.lg` the minimal `test` namespace for compiled test files.
- `rt/wasm/` the runtime, in let-go. A defn marked `^{:twin "core/first"}`
  claims the let-go native it replaces, and the backend routes calls to that
  native to the marked defn (D58). The files load as one runtime under native
  lg as well, with `intrinsics.lg` as a reference implementation of the wasm
  instructions, so the runtime is tested natively before it is compiled.
  `rt/wasm/README.md` has the load-order table, the value kind table and the
  declared differences from native.
- `host/` JS hosts (`lg-wasm-host.js`, `node-host.mjs`), the import ABI
  (`ABI.md`), the REPL, explorer, xsofy and legmacs pages, and their build scripts.
- `checks/` the oracle, the row table `items.tsv`, the gate runner and the
  check scripts.
- `corpus/` inputs and expected outputs for every check, one directory per
  area, plus review corpora and recorded results.
- `tools/` the native inventory and twin manifest (which natives a program
  reaches that the runtime does not provide).
- `DECISIONS.md` the design record. `STATUS.md` the dated row table of work
  items. `FINDINGS.md` things learned that are not decisions.
  `EVAL-NATIVE-SPEC.md` a work order for running the evaluator outside wasm.

## Design in brief

- **One module per program** (D10). Top-level defns are exported functions;
  other top-level forms run in order in an exported `_main`. An op, constant
  or control shape the backend does not handle is a named compile error, not
  a fallback; `corpus/refused` pins those.
- **Integers are hybrid** (D41): `ref.i31` when the value fits 31 bits
  signed, otherwise an `$Int` box. The form is canonical, so equality and
  hashing can rely on it. Booleans are two singleton globals (D22).
- **All runtime types sit in one rec group** (D25), so structs of the same
  shape stay distinct under `ref.test`. let-go `try`/`throw` lower to wasm
  exception handling; `wasm/trap` is kept for internal invariants.
- **Closures** are `$Fn` structs with one code ref per arity and an env
  field (D52); variadics and arities above 4 extend that layout (D83, D150).
- **Native quirks are reproduced, not fixed** (D16): the backend matches
  native lg's overflow, shift and error-text behaviour.
- **Host imports** are a small ABI (D88, `host/ABI.md`): print and write,
  sleep, clocks, getenv, and terminal key and size imports. Blocking imports
  (`sleep`, `read_key`) suspend through JSPI, which needs no COOP/COEP (D91).
- **The match relation** (D12, D13): `checks/oracle.sh` runs a program under
  native lg and through the backend and reports MATCH only when stdout is
  byte-identical, the exit class agrees, and on failure the normalised first
  error line agrees. `.expected` files are snapshots of native output,
  checked first so drift in lg is caught.
- **eval**: `rt/wasm/eval.lg` is a closure-compiling evaluator over reader
  data with let-go's special forms, its core macros as expanders and a core
  table (D160). When a program names `eval` or `*ns*`, `_main` switches to
  the program's namespace and installs a program table of its namespaces,
  vars and macros, so evaluated code resolves the program's own vars (D161).
  `LW_NO_EVAL=1` leaves out the evaluator and the table; modules that never
  reach `eval` are byte-identical either way (D163). `LW_PROGRAM_TABLE=1`
  installs the table without `eval`, for a program whose library inits
  resolve or intern their own vars (D204).
- **Compiling at run time** (docs/SELF-HOST-SPEC.md, stages 3a and 3b-i):
  `rt/wasm/emit.lg` is a second output of the evaluator's front end, a
  baseline emitter of wasm bytes. Built with `LW_EXPORT_RT=1
  LW_RUNTIME_COMPILE=1`, a module carries it and exports its whole runtime;
  `lw compile` turns one form's text into a module that declares the
  host's rec group byte for byte (so its structs are the host's) and
  imports what it calls from the running instance's exports, which is the
  whole import object. The compiled form shares the evaluator's vars,
  values and exceptions: an evaluated `try` catches what compiled code
  throws. Scalar forms, `def`, `fn` without captures and calls through any
  value are in; closures, `try` and collections built from expressions are
  the next stage (D191, D193; rows P10.1, P10.2). Without the flags the
  module's bytes do not change.

## Where it might go

Candidates, none started (as of 2026-10-02):

- A linear-memory target beside WasmGC, specified in
  [docs/LINEAR-TARGET-SPEC.md](docs/LINEAR-TARGET-SPEC.md): tagged i32
  values, a bump allocator first and a precise collector second, a wazero
  runner, and later an Asyncify build for browsers without JSPI.
- Faster compiles: emit binary wasm directly instead of printing and
  reparsing WAT, and cache IR per namespace keyed by source hash.
- `go` blocks and channels, with a scheduler on JSPI.
- Calls through var-table slots, so an evaluated redefinition reaches
  compiled callers.
- A baseline compiler as a second output of the evaluator's front end, so a
  module can compile code at run time without porting the optimizing
  compiler: specified in [docs/SELF-HOST-SPEC.md](docs/SELF-HOST-SPEC.md).

## How this repository is maintained

The code is developed inside a larger private workspace and published from
there with `git subtree push`; this repository is the published view, not a
mirror of that workspace. In practice:

- Issues and pull requests are welcome here. A merged PR is brought back
  into the workspace with `git subtree pull`, so it is not lost when the
  next round is pushed.
- Every push runs `checks/publish-check.sh` as CI. It refuses material that
  belongs to the workspace (its layout names and working notes); the
  pattern is held in a repository secret, so a failure on a PR means the
  text matched something the maintainers keep out of this tree, and the
  CI log shows the line.
- The demos at https://matt.parrett.us/let-go-wasmgc/ are the `gh-pages`
  branch, built by `host/build-pages.sh` on a machine with the
  prerequisites above and pushed by hand after a round.
- Design decisions keep landing in `DECISIONS.md` with the next number.

## Checks

- `checks/items.tsv` has one row per work item: an id, a phase, the exact
  command whose exit 0 means done, and a one-line definition of done.
  `checks/run.sh <id>` runs one row. Exit 2 means the check itself is not
  built yet.
- `checks/gate.sh <n>` runs every row of phase n (1 to 7). Each row's output
  is kept in `${TMPDIR:-/tmp}/lw-gate-<n>/<id>.log`. The trimmed logs of the
  2026-10-02 gate runs are in `corpus/gates/2026-10-02-final/`.
- `checks/oracle.sh` is the only match relation; every MATCH in `items.tsv`
  means this script. `checks/run-corpus.sh <dir>...` runs it over a corpus
  directory.
- Row P1.GATE's `checks/bench-fib.sh` compares against the original probe at
  `../emit-wasm-probe`, which is not in this repo; it fails outside the
  workspace. Gate 1 itself does not depend on it.
- `LW_ATTEST`: by default a gate skips rows whose inputs are unchanged since
  their last green run on this machine (`checks/attest.sh`, keyed by the
  input table in `checks/affected.sh`). Gate decisions are taken with
  `LW_ATTEST=0`, which reruns everything.

## License

MIT; see [LICENSE](LICENSE). [NOTICE](NOTICE) lists the material taken from
let-go, xsofy and legmacs.
