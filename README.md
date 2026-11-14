# let-go-wasmgc

Two experimental compiler backends for [let-go](https://github.com/nooga/let-go),
a Clojure dialect, built on let-go's own optimizer IR:

- **WasmGC** (the default). A program becomes one WebAssembly GC module whose
  functions are real wasm functions over GC structs, with the let-go runtime
  it needs compiled in. The runtime is itself written in let-go
  (`rt/wasm/*.lg`) and goes through the same backend, and a closure-compiling
  evaluator in that runtime gives compiled programs a working `eval`.
- **llvm** (`--target llvm`). The same programs compiled through LLVM IR and
  clang to native binaries over a small C host runtime, on desktops and on
  32-bit and bare-metal boards.

This is an experiment, not part of let-go. Stock `lg -w` builds a wasm
module that runs let-go's bytecode VM inside wasm; neither backend uses the
VM. Every result here is measured against native `lg` by a differential
check, and the design record is [DECISIONS.md](DECISIONS.md).

## See it run

https://matt.parrett.us/let-go-wasmgc/ runs a let-go REPL, an eval and
compile explorer, the compiler itself compiled to a module and compiling in
the page, xsofy (a roguelike) and legmacs (an Emacs-like editor), all in
the browser with no server. The pages need WebAssembly JSPI: as of
2026-10-03 that is Chrome and Edge 137 or newer on desktop; Safari 27 ships
it (iOS included) and Firefox plans it for 153.

## What works

Counts as of 2026-10-20 unless dated otherwise.

- **xsofy** (a roguelike) is playable from the emitted module in the browser
  and in a terminal under node. Its world dumps for seeds 1 to 20 at 60 turns
  are byte-identical to native lg, and a scripted screen dump matches the
  stock build at seed 424242.
- **legmacs** (an Emacs-like editor) boots in the browser and under node.
  343 of its 373 deftests pass under the backend (as of 2026-11-12, #106),
  and 28 of its 30 eval tests pass with the in-module evaluator. Typing a
  `defn` into `*scratch*` and evaluating it with `C-x C-e` works.
- **let-go's own core tests**: 271 of the 273 selected deftests pass, with
  the two remaining ones skipped by name.
- **The jank clojure-test-suite** (241 files of core tests, run through
  `checks/jank-suite.sh` against native lg) passes 168 files (as of 2026-10-25) on the WasmGC
  lane; `corpus/jank/baseline-wasm.tsv` ratchets the count, so a pull request
  may not drop a file. Most of the rest wait on the numeric tower (arithmetic
  over BigInt, Ratio and BigDecimal).
- **On the llvm target** (as of 2026-11-14), the same programs compile to
  native binaries. xsofy and legmacs run on it as interactive
  terminal programs (#106), and legmacs reaches the same 343 of 373
  deftests on both lanes.
- **A browser REPL page** (`host/repl.html`) runs a let-go REPL entirely in
  the module.

Module sizes after `wasm-opt -O3`, brotli-compressed, as of 2026-10-20:

| module | brotli |
|---|---|
| legmacs, with the evaluator | 172 KB |
| legmacs, `LW_NO_EVAL=1` | 121 KB |
| xsofy | 115 KB |
| REPL page module | 82 KB |

## Try it locally

Clone this repository beside checkouts of let-go and legmacs, build lg at
the pinned let-go commit, and install the tools:
[CONTRIBUTING.md](CONTRIBUTING.md#setup) has the list and the commands.
Then, from this repository's root, run legmacs on WasmGC under node
(`C-x C-e` evaluates, `C-x C-c` quits):

```sh
mkdir -p /tmp/lw-play
host/build-legmacs-module.sh /tmp/lw-play/legmacs.wasm
node host/node-host.mjs /tmp/lw-play/legmacs.wasm
```

or as a native binary through the llvm target (about two minutes to
compile; [CONTRIBUTING.md](CONTRIBUTING.md#quick-starts) shows how to keep
the binary):

```sh
LG_ARGS="-source-paths ../legmacs" checks/native-run.sh ../legmacs/main.lg
```

## What doesn't work yet

Named limits, as of 2026-10-25: arithmetic with a BigInt or Ratio operand is
a named error (D230 made the values themselves, `/` of two Ints, the reader's
`1N` and `1/2`, printing, `=`, `hash` and `compare` native-faithful through
`rt/let-go/lang/bignum.lg`; promotion is the next piece of
git-issue:4d19ae0); `go` blocks and channels are not
supported, and `future` runs its body at the call (D162); the evaluator has
no interop, `deftype`, `defprotocol` or `defmulti` (D160). A library
namespace (one under `-source-paths`, since 2026-10-07) and a program's own
namespace (since 2026-10-15) may define `deftype`, `defrecord` and
`defprotocol`: a type is a keyword tag or a map carrying one, a protocol
method one dispatching defn (D204); `extend-type`, `reify` and `defmulti`
are not seen. [FINDINGS.md](FINDINGS.md) lists native
let-go behaviours we met along the way.

## Where it might go

[docs/ROADMAP.md](docs/ROADMAP.md) lists what is started and what is still
a candidate.

## Contributing

Issues and pull requests are welcome; [CONTRIBUTING.md](CONTRIBUTING.md)
covers setup, every quick start, the checks a change runs and how this
repository is published. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) is
the map of the code and [docs/READING-GUIDE.md](docs/READING-GUIDE.md) a
guided walk through it.

## License

MIT; see [LICENSE](LICENSE). [NOTICE](NOTICE) lists the material taken from
let-go, xsofy and legmacs.
