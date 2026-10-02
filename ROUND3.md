# Round 3 plan (revised 2026-10-02 morning after Matt's read; nothing started)

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
