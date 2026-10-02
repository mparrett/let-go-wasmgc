# Round 3 plan, draft 2026-10-02 morning (for Matt's review; nothing started)

Two tracks today. A: get the work out of this machine (upstream path + a demo
page for the team). B: Phase 7, in-module `eval`, which the demo wants because
legmacs without `C-x C-e` is a text editor. A does not wait for B: the demo
ships with eval marked "coming" if B is not green by the time A is ready.

## Track A: upstream path and demo page

A1. **Where the code lives.** Recommendation unchanged from round 1: a
standalone repo made by `git subtree split` of `dev/lower-wasm` (history
preserved, 80+ commits), consuming a stock `lg` at a pinned SHA as a library.
Suggested name without the campaign's internal label: `lg-wasmgc` (or
`letgo-wasmgc`). Path back into let-go stays open: the backend is one `.lg`
file family that `require`s `ir.*`; folding it under `pkg/rt/core/ir/` later is
a move, not a rewrite. Internal-only notes (TinyGo→paserati motive, nnunley's
register-VM WIP) must not travel: grep the split for `paserati`, `nnunley`,
`register-VM`, `lower_wasm` in prose before the first push.
Check: `scripts/scrub-check.sh` exits 0 on the split tree.

A2. **README for strangers.** What it is (IR→WasmGC backend + runtime in a
constrained lg dialect), the numbers with dates (module 417 KB / 112 KB brotli
for xsofy; boot 4.5 s to title vs 9.4 s stock; legmacs 264 ms to the mode
line), how to run the three checks a stranger can run in 5 min (`run-corpus`,
`world-parity.sh 3`, `browser-boot.sh --xsofy`), the named-limits list from
INVENTORY, the decision log pointer. No "campaign", no agent narrative; that
stays in joint (TOUR.html, DECISIONS.md).

A3. **Demo page.** One static page, two playables side by side and a table:
xsofy (the real shell) and legmacs (stock xterm shell), each with "lower-wasm
lane" vs "stock lg -w lane" boot times measured live in the visitor's browser
(`?seed=424242` for xsofy so it is byte-identical to native), the size table,
and a "how it works" paragraph with links. Hosting: GitHub Pages of the new
repo (`gh-pages` from `demo/`), never nooga's domain; the stock lane needs
COI, so the demo page serves the stock bundle only through its
coi-serviceworker fallback or omits the stock playable and keeps its numbers.
Check: Playwright visits the page, both lanes reach their first frame, the
table renders.

A4. **The upstream spin-offs, generic.** Three issues on nooga/let-go from the
dossier, each phrased as a plain bug with a native-only repro:
`ir.build/build-loop` re-binds loop vars into the enclosing scope (D148),
reader counts `;;` inside a map literal as a form (D147), `binding *ns*`
around `eval` leaks (D124). Search open issues first (CLAUDE.md rule).
Prose pipeline: draft → outbound-prose-review → aislop → Matt.

A5. **Tell the team.** A short post (Matt's voice) with the demo link, the
numbers, what is NOT there (eval, go blocks, regex flags, sorted-*-by), and
the ask (try it, break it). Draft in docs-xsofy/outbound/.

## Track B: Phase 7, in-module eval

Three shapes, with a recommendation.

B-i. **Interpreter in the runtime dialect** over the reader's data (`rt/wasm/
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

B-ii. **The IR pipeline compiled through the backend**, so the module lowers
new code to wasm at run time and asks the host to `WebAssembly.instantiate` it
and link it (a second module importing the first's tables/types). Cost: the
compiler (`ir.build`, passes, `lower_wasm.lg` itself, ~8 k lines of
unconstrained lg with reflection) must first run under the backend; the single
`rec` group makes cross-module type identity a real problem; the host ABI
grows an instantiate-and-link call. Risk: high, weeks, and the result is the
whole compiler in every page. Not for this round.

B-iii. **Host-side eval**: ship the stock lg VM wasm (7 MB) beside the module
and route `eval` to it. Defeats the size story and splits state between two
heaps. No.

**Recommendation: B-i**, scoped to what legmacs' REPL/eval-last-sexp/
eval-buffer use, with `go`/`future`/`promise` kept as Phase 8 (a scheduler on
JSPI is a separate design) and regex flags folded into B-i's reader work only
if cheap. Finish line: a `P7.GATE` with rows:

| row | check |
|---|---|
| P7.0 | `corpus/eval/` oracle: native `(eval (read-string s))` vs module, 200+ forms across special forms, core fns, closures, recursion, errors (message parity) |
| P7.1 | legmacs `repl_mode_test` 7/7 and `letgo_mode_test` ≥ 20/23 (the eval-dependent files), P6.2 bar raised accordingly |
| P7.2 | `legmacs-parity.sh` script 6: type a defn in *scratch*, `C-x C-e`, call it, see the echo; byte-identical |
| P7.3 | eval-buffer of `legmacs/modes/comment.lg` in the module defines its commands (a mode installed at run time works) |
| P7.4 | size/boot deltas recorded: the interpreter's cost in the module (expect +60–120 KB brotli) |
| P7.R | adversarial review of the evaluator (own corpus) |

## Order for today

1. A1 split + scrub + README (runner, ~2 h) while B-i starts (one Opus, src-free: it is all `rt/wasm/eval.lg` + reader).
2. A3 demo page (one Opus, host/ only) in parallel.
3. A4 three issues drafted, not posted, for Matt's read.
4. B-i rows as they land; P7.GATE if it lands today, else the demo says "eval: coming".

Nothing is pushed or posted until Matt says which of A1/A3/A4 go first.
