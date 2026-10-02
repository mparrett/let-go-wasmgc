# Round 4 candidates (notes, 2026-10-02 evening; nothing started, nothing decided)

Written during round 3's final gate so the ideas are findable. Order is the
runner's recommendation, not a decision; Track B (repo split, Pages, README,
lab issue, let-go note, team post) comes before any of these.

## 1. Compile-time work (cross-team, let-go-lab#43)
Per-namespace IR + type cache keyed by source hash and require closure (the
`.rtlib` idea extended to program namespaces); binary wasm emission instead of
12.4 MB of WAT printed and parsed back; validation off in dev loops. Numbers
and the per-pass table: `corpus/buildtime-2026-10-02.md` and joint
`docs/project_incoming/letgo-compile-time-spike-2026-10-02.md`. The census on
the VPS (below) feeds the binary-emitter half.

## 2. go blocks and channels
A scheduler on JSPI; the plan's "Phase 8". Biggest remaining named limit for
legmacs (every file that uses `go`; futures run eagerly and are never pending,
D162). Design-heavy, medium size.

## 3. Redefinition reaching compiled callers
Calls through var-table slots instead of direct calls, so an evaluated
redefinition replaces the compiled one everywhere. About half a day; small
speed cost; removes the most surprising REPL behaviour (D160 limit).

## 4. The evaluator beyond wasm ("eval.lg is not wasm-specific")
`rt/wasm/eval.lg` (new in round 3, D160) is a let-go interpreter written in
let-go: plain lg over reader data, already running natively in the test tier
(corpus/intrinsics/eval_test.lg, 122 deftests against native `eval`). It is
coupled to the runtime's value model and registry (kind dispatch, string
constructors, wasm.natives' ns/var registry, the backend's program table),
not to wasm. Factoring those touchpoints into a seam of ~10 functions with a
native implementation over real namespaces/vars would give let-go programs
compiled ahead of time (gogen/AOT, TinyGo lanes) an `eval` for the cost of
linking one lg file: today an AOT binary has no VM and no eval, the same gap
legmacs had in the module before round 3. Native-only framing, so it
upstreams cleanly. Oracle exists: the P7.R corpus and the native-tier
deftests run both implementations. Moderate effort, not a rewrite.
(Raised by Matt's friend, 2026-10-02.)

## 5. Runtime compile, staged so it is not the ocean
The backend running inside its own output. The staging that avoids porting
`ir.*` (8 k lines of unconstrained lg) under the backend: give the evaluator
a SECOND OUTPUT. Its front end already reads, macroexpands, resolves through
the program table and handles destructuring/arities; a baseline compiler emits
wasm from that instead of closures (everything boxed, no typeinfer, no licm;
~2 k lines plus a binary encoder). The optimising compiler stays on the host.
Stages, each with its own oracle:
1. binary encoder in lg, used by the host driver first (bytes identical to
   wasm-tools' parse of today's WAT; also item 1's win);
2. the census (`tools/reach.sh` over the evaluator's front end + emitter;
   `checks/native-twins.sh` for the MISSING list; being run on the VPS);
3. compile a subset with no linking: `(compile-fn 'form)` returns bytes;
   subsets in the corpus's own order (arithmetic/locals, conditionals/loops,
   closures, program vars, multi-arity/variadic); oracle = instantiate on
   the host and compare with eval over the same directories;
4. linking in the module: the host instantiates the bytes as a second module
   importing the first's exports (WasmGC types are structural, so identical
   rec groups match), writes the fn into the var slot; oracle = REPL
   `(compile ..)` agrees with `(eval ..)`;
5. policy: a defn evaluated twice gets compiled, or legmacs eval-buffer
   compiles by default; measured on fib interpreted vs baseline vs AOT.
Estimate before the census: 3-5 round-days; the census turns that into a
number.

## 6. Smaller named limits
Catch dispatch by class; a small interop subset (`.Format`, `now`); pending
futures; macro error frames (D165); `System/nanoTime` and `Math/sqrt` in the
evaluator's core table (two REPL examples had to be rewritten around them).

## Standing head start on another box (4 vCPU VPS)
Clone joint-xsofy + let-go@4e76921 + xsofy + legmacs@187fea2, build
`lg-bin/lg-4e76921230`, node/binaryen/wasm-tools/Playwright, prove with
`checks/run.sh P2.1` (14/14). Then the census, read-only: `tools/reach.sh`
over the compiler and over the evaluator, `checks/native-twins.sh` on the
lists, a report in docs/project_incoming grouped by kind (reflection,
namespace objects, var meta, macroexpansion via the VM, file I/O), driver
test-mode needs separated from compiler needs. Knobs: `LW_SLOTS=2
LW_GATE_J=1 GOMAXPROCS=4`, shared `LW_MODULE_CACHE`/`LW_RTLIB_DIR`,
`LW_NO_OPT=1`; never gates or the census rows P1.5/P1.6 there. Mechanical
half Sonnet, grouping/judgement Opus.
