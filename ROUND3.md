# Round 3 plan (revised 2026-10-02 morning after Matt's read; Track A STARTED 2026-10-02 ~08:00 PDT under /loop; Track B HOLD)

Track A is Phase 7, in-module `eval`: Matt wants to test-drive the interpreter
before deciding anything about the public surface. Track B (out of this
machine: repo split, README, demo page, upstream issues) is **HOLD**: it is
written down so the shape is agreed, and NOTHING in it runs in a loop cycle
until Matt says so explicitly in conversation. A loop tick that finds Track A
finished STOPS and reports; it does not start Track B.

## Track A: Phase 7, in-module eval (the interpreter)

Three shapes, with a recommendation.

A-i. **Interpreter in the runtime dialect** over the reader's data (`rt/wasm/
reader.lg` already yields EDN/code data). A tree-walking evaluator: special
forms (def, fn/fn*, let, if, do, loop/recur, quote, try/throw, binding, ns/
in-ns), macros via a small macroexpander that reuses the program's own macro
table when it is in the module (defmacro inside eval stays a limit), calls into
the module's natives/twins through the var table and the existing `invoke`
ABI. Interpreted fns are `Fn` values like any other, so they can be stored in
atoms, passed to `map`, bound to keys. Cost: ~1.5–2 k lines of dialect, no
backend change, slow (10–50× slower than compiled; fine for a REPL). Risk: low;
every piece has an oracle (native `eval` of the same forms). Estimate: one
round-pace day for expressions + defs + fns + macros from core; eval-buffer of
a legmacs mode file maybe two.

A-ii. **The IR pipeline compiled through the backend**, so the module lowers
new code to wasm at run time and asks the host to `WebAssembly.instantiate` it
and link it (a second module importing the first's tables/types). Cost: the
compiler (`ir.build`, passes, `lower_wasm.lg` itself, ~8 k lines of
unconstrained lg with reflection) must first run under the backend; the single
`rec` group makes cross-module type identity a real problem; the host ABI
grows an instantiate-and-link call. Risk: high, weeks, and the result is the
whole compiler in every page. Not for this round.

A-iii. **Host-side eval**: ship the stock lg VM wasm (7 MB) beside the module
and route `eval` to it. Defeats the size story and splits state between two
heaps. No.

**Evaluator shape inside A-i (decided at dispatch, not before; recorded here
so the implementer and Matt see the same options).** Three ways to build the
same semantics: (1) a plain tree-walker that re-dispatches on the form at
every evaluation; (2) a closure-compiling evaluator ("compile to closures"):
one pre-pass turns each form into a dialect `Fn` that takes an environment, so
the dispatch on syntax happens once per form instead of once per evaluation;
2–4× faster than (1) for the same code size, still simple, and it maps onto
what the module already has (every closure is an `Fn`, calls go through the
existing invoke ABI); (3) a CEK machine (explicit continuation, no host-stack
recursion, free tail calls, cheap try/throw), which Matt's `let-rs` and
`wallisp` siblings have; wallisp measured bytecode 2.3–3.9× over a tree-walker
and CEK between them. Plan: (2) first, with tail calls trampolined so a `loop`
or self-recursion in evaluated code does not grow the wasm stack; move to a
CEK (3) only if deep recursion in evaluated code becomes a real limit for
legmacs' eval-buffer. Bytecode in the dialect is out: it is a second VM.
Working comes first, speed second; `P7.4` records the cost either way.

**Recommendation: A-i**, scoped to what legmacs' REPL/eval-last-sexp/
eval-buffer use, with `go`/`future`/`promise` kept as Phase 8 (a scheduler on
JSPI is a separate design) and regex flags folded into A-i's reader work only
if cheap. Finish line: `checks/gate.sh 7` green with gates 1–6 still green (`LW_ATTEST=0`). Rows (to be appended to `checks/items.tsv` before any dispatch, each check exiting 2 until built):

| row | check |
|---|---|
| P7.0 | `corpus/eval/` oracle: native `(eval (read-string s))` vs module, 200+ forms across special forms, core fns, closures, recursion, errors (message parity) |
| P7.1 | legmacs `repl_mode_test` 7/7 and `letgo_mode_test` ≥ 20/23 (the eval-dependent files), P6.2 bar raised accordingly |
| P7.2 | `legmacs-parity.sh` script 6: type a defn in *scratch*, `C-x C-e`, call it, see the echo; byte-identical |
| P7.3 | eval-buffer of `legmacs/modes/comment.lg` in the module defines its commands (a mode installed at run time works) |
| P7.4 | size/boot deltas recorded: the interpreter's cost in the module (expect +60–120 KB brotli) |
| P7.5 | the interpreter is reachable from the node host and the browser host the same way (`(eval (read-string "..."))` from a program, and legmacs `C-x C-e`), so Matt can test-drive it in `lw-play` |
| P7.R | adversarial review of the evaluator (own corpus, read-only) |
| P7.GATE | `checks/gate.sh 7 && gate.sh 1..6` with `LW_ATTEST=0` |

Dispatch shape: one Opus on `rt/wasm/eval.lg` (+ reader additions) with the P7.0 corpus as its oracle; a second Opus only when P7.0 is green, for P7.1–P7.3 (legmacs wiring); P7.R as a read-only reviewer; the runner owns rows, verification, commits, STATUS, DECISIONS (D159+). Same rules as rounds 1–2 (AGENTS.md; ≤3 Opus; src/ one at a time; every report verified by rerunning its row).

Test-drive for Matt when P7.5 is green: `node host/node-host.mjs /tmp/lw-play/legmacs.wasm`, type `(defn f [x] (* x 2))` then `C-x C-e`, then `(f 21)` `C-x C-e` → `42` in the echo area; and the browser at :8261 the same way.


## Phase 7 seam (binding for agents A and B; written 2026-10-02 before dispatch)

Two builders work in parallel on opposite sides of one interface. A owns
`rt/` (and `corpus/eval/`, `corpus/intrinsics/eval_test.lg`); B owns `src/`
(and `corpus/eval/program/`). Neither edits the other's files; the runner
integrates. Everything below is the contract; anything not here is the
owner's call, recorded in the file header.

**Where and in what dialect.** `rt/wasm/eval.lg`, namespace `wasm.eval`, in
PLAIN lg as `rt/wasm/natives.lg` is (load order 17 in the README table, which
`src/lw_rt.lg` reads; requires wasm.natives, wasm.reader, wasm.core, wasm.seq,
wasm.str, wasm.phm). Plain lg because none of it is a hot path and the
backend links a runtime defn only when the program reaches it: a program
that never calls `eval` (xsofy) pays nothing. Twins are claimed the usual way
(`^{:twin "core/eval"}`), so no src change is needed to route `eval`.

**Evaluator shape.** Closure-compiling: `(compile form cenv)` turns a form
into an lg fn of the run-time environment once; evaluation runs the closures.
Evaluated fns are ordinary lg `fn` closures (multi-arity and `&` dispatch
inside), so they are `Fn` values and work wherever a fn works (atoms, `map`,
key bindings, `apply`). `loop`/`recur` and fn-tail `recur` through a Recur
marker and a loop in the compiled closure. `try`/`catch`/`finally` over lg's
try (finally = run after catch and rethrow). Tail calls between evaluated fns
are NOT trampolined in the first cut (named limit: deep non-loop recursion in
evaluated code grows the wasm stack); add trampolines only if P7.1 needs
them. Working first; P7.4 records the cost.

**Namespaces and vars live in wasm.natives' registry** (`:cur`, `:nss`,
`:cells`, `:aliases`), A extends it:
- `(wasm.natives/current-ns)` → the stand-in `<ns cur>`; B routes reads of
  `*ns*` to it. `in-ns` already sets `:cur`; `(ns foo (:require [a :as b]))`
  in evaluated code = add-ns! + set `:cur` + record aliases/refers under
  `[:aliases "foo"]` / `[:refers "foo"]`; `(require '[a :as b])` the same for
  `:cur`. `ns-resolve` becomes a twin (legmacs' tests call it).
- `def`/`defn`/`defmacro` in evaluated code intern a cell `cur/name` (value,
  meta, `:macro` flag). **Evaluation never writes a program var**: a
  redefinition shadows it for evaluated code only; compiled callers keep the
  old definition (named limit, same family as with-redefs').

**Symbol resolution** for `s` evaluated in `cur`, in order: local env → cell
`cur/s` → program table `cur` `:vars s` → program table `cur` `:refers s` →
core table `s` (unqualified only) → for `a/s`: `a` through registry aliases of
`cur`, then program-table `:aliases` of `cur`, then as a full ns name →
cells/program table of that ns; `core/s`, `clojure.core/s`, `let-go.core/s`,
`user/s` → core table. Not found → raise native's text exactly: `Can't
resolve s in this context` (native wraps it in `CompileError: compiling
function position` for a call; match what `(ex-message e)` shows, which P7.0
pins per case). Arity errors use native's `function <fn ...> expected N
args, got M` shape only where the oracle can compare (the fn address cannot
match; the corpus avoids printing it).

**The core table is A's, in eval.lg**: a map from name (Str) → fn value for
the REPL core set (arithmetic/compare, seq and collection fns, strings,
atoms, printing, `apply`, `str`, `pr-str`, `read-string`, `eval` itself,
`type`, `instance?`-free predicates, `ex-info`/`ex-message`, …; aim ≥150).
Written as plain lg values (`{"map" map "reduce" reduce ...}`), so the
backend links each twin because eval.lg names it. `ns-publics`/`all-ns`
need not list it.

**The program table is B's, built by the backend when the program reaches
`core/eval`** and installed from ns-init after every library ns-init:

```
(wasm.eval/install-program-table!
  {"legmacs.main" {:aliases {"buf" "legmacs.buffer" ...}
                   :refers  {"vibe" "legmacs.vibe"}
                   :vars    {"x" <var stand-in> ...}
                   :macros  {"defcommand" <macro fn> ...}}
   "legmacs.buffer" {...} ...})
```

Keys are Str. A var stand-in is the `#'ns/name` meta'd Symbol with the
`:lw/var` 0-arg getter that `wasm.core/var-value` already reads
(var-const-form), with meta cut to `:lw/var` (+ `:name`, `:ns`) to keep the
table small; B may instead emit one dispatch fn and lazy stand-ins if the
eager map costs more than ~40 KB brotli on legmacs (P7.4 decides; either way
A only ever calls `wasm.core/var-value`). `:macros` holds each program
`defmacro` compiled as a hidden fn of its forms (its body is list/seq/symbol
code; syntax-quote expands to list/concat/seq calls the runtime has); A calls
it with the unevaluated args (`&form`/`&env` as nil) and evaluates the
expansion. `:macros` is P7.3's dependency and B's second deliverable; the
table with `:aliases`/`:refers`/`:vars` is the first. Every program ns is
listed (legmacs' aliases are in `legmacs.main`, the tests' in their own ns).

**Core macros are evaluator built-ins** (expanders in eval.lg, not program
macros): defn defn- fn (named, multi-arity, `&`, destructuring in vector and
map forms with :keys :as :or) let letfn loop if if-not if-let when when-not
when-let cond condp case and or -> ->> as-> some-> some->> doto dotimes doseq
(with :let/:when) for (basic) while do quote var def defmacro (non
syntax-quote bodies) binding set! (on a cell) try catch finally throw
lazy-seq delay comment with-out-str (through `core/with-out-str*` with a
thunk) deftest-free. Everything else is a call. Record each omission as a
limit in the header.

**Reader.** `read-string` must read code: `'x`, `#'x`, `@x`, `^{..} x` and
`^:kw x`, `#(... % %1 %&)` → `(fn* [...] ...)`, `::kw` in `:cur`; the
existing reader_test stays green; new limits named. `read-all-string` is
lw-ext's; it must return the same forms.

**Oracle for A: `corpus/eval/`**, plain programs that print the result of
`(eval (read-string "..."))` or `(eval 'form)`, grouped by directory
(special/, macros/, fns/, errors/, ns/, reader/); 200+ forms; each file
MATCHes native lg through `checks/run-corpus.sh corpus/eval`. The native tier
(`checks/run-intrinsics-native.sh`, `corpus/intrinsics/eval_test.lg`) covers
the compile step under native lg. `corpus/eval/program/` (B's) needs the
program table: programs with their own defns, aliases and a macro that
evaluated code calls.

**Routes B owns in src** (one src item in flight, as always): `*ns*` read →
`wasm.natives/current-ns`; the program-table emission and its ns-init call;
program macros compiled as hidden fns; nothing else in src unless A names a
backend gap in a report (then B takes it; A never edits src).

**Entry points legmacs uses** (`legmacs/modes/letgo.lg`, `vibe.lg`):
`(eval form)`, `(read-string s)`, `(read-all-string s)`, `(in-ns sym)`,
`(ns-name *ns*)`, `(ns-resolve ns sym)`, `with-out-str` + `(binding [*err*
*out*] ...)` around eval. P7.1's tests also `deref` a resolved var and call
it.

## Track B (HOLD): upstream path and demo page

**HOLD. Do not start any B row from a loop tick. Matt decides after test-driving the interpreter.**

B1. **Where the code lives.** Recommendation unchanged from round 1: a
standalone repo made by `git subtree split` of `dev/lower-wasm` (history
preserved, 80+ commits), consuming a stock `lg` at a pinned SHA as a library.
Suggested name without the campaign's internal label: `lg-wasmgc` (or
`letgo-wasmgc`). Path back into let-go stays open: the backend is one `.lg`
file family that `require`s `ir.*`; folding it under `pkg/rt/core/ir/` later is
a move, not a rewrite. Internal-only notes (TinyGo→paserati motive, nnunley's
register-VM WIP) must not travel: grep the split for `paserati`, `nnunley`,
`register-VM`, `lower_wasm` in prose before the first push.
Check: `scripts/scrub-check.sh` exits 0 on the split tree.

B2. **README for strangers.** What it is (IR→WasmGC backend + runtime in a
constrained lg dialect), the numbers with dates (module 417 KB / 112 KB brotli
for xsofy; boot 4.5 s to title vs 9.4 s stock; legmacs 264 ms to the mode
line), how to run the three checks a stranger can run in 5 min (`run-corpus`,
`world-parity.sh 3`, `browser-boot.sh --xsofy`), the named-limits list from
INVENTORY, the decision log pointer. No "campaign", no agent narrative; that
stays in joint (TOUR.html, DECISIONS.md).

B3. **Demo page.** One static page, two playables side by side and a table:
xsofy (the real shell) and legmacs (stock xterm shell), each with "lower-wasm
lane" vs "stock lg -w lane" boot times measured live in the visitor's browser
(`?seed=424242` for xsofy so it is byte-identical to native), the size table,
and a "how it works" paragraph with links. Hosting: GitHub Pages of the new
repo (`gh-pages` from `demo/`), never nooga's domain; the stock lane needs
COI, so the demo page serves the stock bundle only through its
coi-serviceworker fallback or omits the stock playable and keeps its numbers.
Check: Playwright visits the page, both lanes reach their first frame, the
table renders.

B4. **The upstream spin-offs, generic.** Three issues on nooga/let-go from the
dossier, each phrased as a plain bug with a native-only repro:
`ir.build/build-loop` re-binds loop vars into the enclosing scope (D148),
reader counts `;;` inside a map literal as a form (D147), `binding *ns*`
around `eval` leaks (D124). Search open issues first (CLAUDE.md rule).
Prose pipeline: draft → outbound-prose-review → aislop → Matt.

B5. **Tell the team.** A short post (Matt's voice) with the demo link, the
numbers, what is NOT there (eval, go blocks, regex flags, sorted-*-by), and
the ask (try it, break it). Draft in docs-xsofy/outbound/.

## Order

1. Append the P7 rows to items.tsv and the affected table (runner). Dispatch A-i.
2. Verify, commit per row; P7.5 as early as the evaluator evaluates `(+ 1 2)`, so Matt can start test-driving while the rest lands.
3. P7.GATE. Then STOP the loop and report. Track B waits for the conversation.
