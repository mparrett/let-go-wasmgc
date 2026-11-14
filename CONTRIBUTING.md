# Contributing

Issues and pull requests are welcome. This page is for building and
changing the backends: what to install, how to run things, how a change is
checked, and how this repository is published. [README.md](README.md) is
the overview, [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) the map of the
code, [docs/READING-GUIDE.md](docs/READING-GUIDE.md) a guided walk through
it, and [docs/WORKFLOW.md](docs/WORKFLOW.md) how work moves through the
issue board.

## Setup

The checks and build scripts find their inputs under one root, `LW_ROOT`,
resolved by `checks/env.sh`: it is the directory holding `let-go/`,
`xsofy/`, `legmacs/` and `lg-bin/`. It is found automatically when this
repository is cloned beside those checkouts; otherwise set `LW_ROOT`, or
override the individual paths (`LG`, `LETGO`, `XSOFY`, `LEGMACS`).

- **Go 1.25 or newer** for the linear runner (2026-10-03).
- **Native lg built from let-go commit dbccbf0f**, at
  `$LW_ROOT/lg-bin/lg-dbccbf0f63` or wherever `LG` points. The driver runs
  under this lg and uses let-go's IR passes from it. From `$LW_ROOT`, with
  Go 1.27 or newer (let-go's `go.mod` at the pin; with the default
  `GOTOOLCHAIN=auto`, an older Go downloads it):

  ```sh
  git clone https://github.com/nooga/let-go let-go
  git -C let-go worktree add --detach ../lg-build dbccbf0f
  make -C lg-build build
  mkdir -p lg-bin && cp lg-build/bin/lg lg-bin/lg-dbccbf0f63
  ```
- **A let-go git checkout** (`$LETGO`, default `$LW_ROOT/let-go`) that
  contains commit dbccbf0f: `src/lw_rt.lg` reads let-go's `pkg/rt/core/*.lg`
  at that commit with `git show`, and fails with a message naming the path
  when it cannot.
- **wasm-tools** on `PATH` (WAT to binary).
- **LLVM's clang**, for `--target llvm`: `/opt/homebrew/opt/llvm/bin` by
  default (`brew install llvm`), or set `LLVM_BIN`. The bare-metal board
  profiles also need lld (`brew install lld`, or `LLD_BIN`), and
  `qemu-system-arm` to run the armv7 boards. Their builds link LLVM's
  compiler-rt builtins, which `checks/build-builtins.sh` compiles with
  cmake, ninja and git from a clone of llvm-project at the installed
  clang's tag: the first build needs network access, and a new clang
  version, triple or flag set builds them again. As of 2026-11-14 that
  script uses macOS's `md5`.
- **binaryen's wasm-opt** (and `wasm-merge` for `checks/browser-boot.sh`):
  the Homebrew install when present, otherwise the one on `PATH`; set
  `WASM_OPT` / `WASM_MERGE` to choose another. Used by the module build
  scripts in `host/`. `LW_NO_OPT=1` skips it.
- **brotli**, for the size lines the build scripts print.
- **node** with WasmGC, wasm exception handling and JSPI. We develop on
  node 25. `src/run.mjs` and `host/node-host.mjs` set their own stack sizes.
- **wasmtime** (47 or later, from `PATH` or `~/.wasmtime/bin`; `WASMTIME`
  names another) for the wasmtime host lane: row P4.5 runs `corpus/wasm` and
  `corpus/scalar` through `checks/wasmtime-run.sh`, and `checks/browser-boot.sh`
  has a wasmtime row (D232; GC, exceptions, function references and tail
  calls enabled). Without it P4.5 is SKIP, that row is SKIP, and node-host
  alone decides P4.0 when Chromium is missing too (D227).
  `LW_REQUIRE_WASMTIME=1` turns the SKIP into a FAIL.
- **Chromium through Playwright** for the browser lanes
  (`checks/browser-boot.sh`, `checks/lane5.sh`, `checks/turn-time.sh`,
  `checks/eval-hosts.sh`,
  `checks/size-boot.sh`, the `*-page-check.mjs` scripts). Playwright is
  the first of these whose Chromium launches (`checks/playwright.mjs`):
  `LW_BROWSER_TOOLS/browser-smoke-playwright/` when that is set; the version
  `package.json` pins, after `npm ci` (or on `NODE_PATH`); a global
  `npm i -g playwright`; then `playwright` on PATH, a Node install or a
  Python one (its bundled Node driver). Each Playwright version runs only its
  own browser build (`npx playwright install chromium`), and a candidate
  whose build is missing is passed over, so the checks reuse the browser
  already on the machine. Without it the rows do not fail: their browser lanes
  report SKIP with the reason (`checks/browser-probe.mjs`), node-host and
  wasmtime decide P4.0, node-host and legmacs decide P7.5, and the
  browser-only rows exit 2 with a SKIP line (D227), which the gate reports as
  `# SKIP`. `LW_REQUIRE_BROWSER=1` turns that SKIP
  into a FAIL on a machine where the browser lanes are expected to run.
  The COI server and the shell injector live in `host/` (`coi-serve.py`,
  `inject-shell.sh`) since 2026-10-21 and need nothing outside the repository.
- **xsofy and legmacs checkouts** (`$XSOFY`, `$LEGMACS`) for those corpora.
  Multi-namespace programs name their source roots through `LG_ARGS`, as
  row P7.3 in `checks/items.tsv` does:
  `env LG_ARGS="-source-paths $LW_ROOT/legmacs" checks/run-corpus.sh corpus/eval-buffer`.

Environment variables that matter:

| variable | effect |
|---|---|
| `LW_BROWSER_TOOLS` | optional: a directory holding `browser-smoke-playwright/`, tried before the pinned, global and PATH Playwrights (`checks/playwright.mjs`); `checks/size-boot.sh` also reads its boot probe from there |
| `LW_REQUIRE_BROWSER=1` | a browser lane that cannot run is a FAIL, not a SKIP (D227) |
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

## Quick starts

Run from the repo root. The first compile after any change to `src/` or
`rt/` builds the runtime library, which took about two minutes as of
2026-10-20 (five scalar programs from a cold cache in 144 s);
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

Build and serve the compiler itself as a module, then open
http://localhost:8264/compile.html. Paste a let-go program: the backend,
carried as a program (D206, D211), compiles it inside the module in a worker,
`host/wat-asm` (wasm-tools' text parser compiled to wasm, needs cargo with the
wasm32-unknown-unknown target) assembles the text, and the page runs the
result. The first build takes minutes (the P12 rows' build times plus
wasm-opt) and is cached; a compile in the page takes tens of seconds:

```sh
host/build-compile-serve.sh /tmp/lw-compile
python3 -m http.server 8264 -d /tmp/lw-compile
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

Run legmacs as a native binary through the llvm target. The first run
builds the llvm runtime library (about four minutes from a clean clone as
of 2026-11-14), and every run compiles the program again (about two
minutes for legmacs). `KEEP=1` keeps the build directory and prints
`kept <dir>` on exit:

```sh
KEEP=1 LG_ARGS="-source-paths ../legmacs" checks/native-run.sh ../legmacs/main.lg
```

The line comes on stderr after the editor exits. Set `KEPT` to that
directory; the binary in it, `m`, then starts at once:

```sh
KEPT=/the/directory/printed/after/kept
cd ../legmacs && "$KEPT/m" main.lg
```

## Targets

The WasmGC hosts need WebAssembly JSPI (browser versions are in the
README). Binaryen's Asyncify cannot stand in, because it spills locals to
linear memory and these modules hold GC references in locals
(`wasm-opt --asyncify` asserts on them).

**The llvm target.** Since 2026-11-09 (#78), `--target llvm` compiles a
program to LLVM IR and, through clang, to a native binary over a small C
host runtime (`host/native/`). WasmGC remains the default target; the two
share the driver and the IR pipeline, and their runtimes (`rt/wasm/`,
`rt/llvm/`) are kept at parity by the phase 13 rows. `checks/native-run.sh`
compiles, links and runs a program, and behaves like `lg` on stdout and
exit status. `LW_PROFILE` is the only way to choose its hardware profile,
32-bit and bare-metal boards included: the runner passes it to the driver
and links and runs for the same profile.
[docs/LLVM-TARGET-SPEC.md](docs/LLVM-TARGET-SPEC.md) is the spec.

As of 2026-10-03, `--target linear` (or `LW_TARGET=linear`) selects an
experimental linear-memory module with a leaking allocator; WasmGC remains
the default. Run it with `checks/wasm-run-linear.sh`. The Go host uses
[nooga/wazero](https://github.com/nooga/wazero) pinned at
`v1.12.1-0.20260911172836-0ec6142ae8c7`, with
`experimental.CoreFeaturesTailCall` and
`experimental.CoreFeaturesExceptionHandling` enabled and GC disabled.
Milestone corpus results and named refusals are recorded in STATUS.md.

## Checks

- `checks/items.tsv` has one row per work item: an id, a phase, the exact
  command whose exit 0 means done, and a one-line definition of done.
  `checks/run.sh <id>` runs one row. Exit 0 is done, 1 failing, 2 skipped (a
  tool or host lane is missing here; the row's last line starts with `SKIP`
  and gives the reason), 3 not built yet. A fifth column names the issue that owns a known
  failure.
- `checks/gate.sh <n>` runs every row of phase n (the second column of
  `items.tsv`) and reports them as TAP (D228): `ok`, `ok … # SKIP <reason>`,
  `not ok … # TODO git-issue:<id>` for a row with an owning issue, `not ok`
  otherwise; it fails on any plain `not ok`, and on a TODO row that passes.
  The stream is TAP 13, with each row's work time (`duration_ms`, wall time
  less any time blocked on the slot pool, which is `wait_ms`) in a block under
  its line, and each row is logged with its time, the revision and the
  machine's load to `$LW_STATE/gate-times.tsv`, or to `$LW_GATE_TIMES` when set
  (D229). Each row's output
  is kept in `${TMPDIR:-/tmp}/lw-gate-<n>/<id>.log`. The trimmed logs of the
  2026-10-02 gate runs are in `corpus/gates/2026-10-02-final/`.
- `checks/oracle.sh` is the only match relation; every MATCH in `items.tsv`
  means this script. `checks/run-corpus.sh <dir>...` runs it over a corpus
  directory.
- Row P1.GATE's `checks/bench-fib.sh` compares against the original probe at
  `../emit-wasm-probe/ext/gen-ext.lg`, which is not in this repo; without it
  the row exits 2 with a `SKIP` line, which the gate reports as `# SKIP`.
  Gate 1 itself does not depend on it.
- `LW_ATTEST`: by default a gate skips rows whose inputs are unchanged since
  their last green run on this machine (`checks/attest.sh`, keyed by the
  input table in `checks/affected.sh`). Gate decisions are taken with
  `LW_ATTEST=0`, which reruns everything.

Gate history:

- Gates 1 to 7 passed on 2026-10-02 with `LW_ATTEST=0` (gate 7 rerun green
  the same evening, D169, D170) and gate 12, the self-compilation stage, on
  2026-10-09 (D212). Since then every pull request is held to the rows it
  touches; the GC byte guard (`checks/gc-byte-identity.sh`, P8.0) is
  advisory since D228, and the oracle rows decide. The test counts
  above were re-measured on 2026-10-20.

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
  setup above and pushed by hand after a round.
- Design decisions keep landing in `DECISIONS.md` with the next number.

## Issues

Work items live in this repository as git notes under `refs/notes/issue-*`,
managed with `git-issue` (the git-issue-tracker project on GitHub).
Once per clone:

```sh
git issue setup-sync enable      # hooks + fetch refspec for the notes
git fetch origin 'refs/notes/issue-*:refs/notes/issue-*'
# the evidence each push records (make -f checks/workflow.mk start checks it)
git config --add remote.origin.fetch '+refs/notes/evidence:refs/notes/remotes/origin/evidence'
git issue list
git issue ready                  # open, unblocked, by priority
```

Reference an issue from a commit with a trailer (`Issue: #<id>`, `Fixes: #<id>`,
`Closes: #<id>`); `git issue scan-commits` finds them. Push soon after editing
an issue: the tool's default fetch refspec is forcing and a fetch can replace a
local issue ref that has unpushed edits (tracked as git-issue-tracker #e2dfdaa).
