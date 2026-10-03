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

## 7. Linear-memory target (Matt's ask, 2026-10-02 late; SHELVED to the weekend)
Matt's words, lightly condensed: "First we need a leaking allocator. (1) a
`--target linear` switch in the driver, WasmGC stays the default; (2) in
lower_wasm.lg switch the value representation to a tagged i32 (fixnum low
bit, mirroring D41), lower struct.*/array.* to bump-allocate plus loads and
stores, casts to header type-id checks, call_ref/return_call_ref to
call_indirect/return_call_indirect; (3) a wazero runner beside
checks/wasm-run.sh so checks/oracle.sh can compare outputs, noderati with a
small host script is the quickest; (4) done when corpus/scalar/ gives MATCH
under wazero; legmacs booting under noderati comes after. Milestone 2, the
precise collector with a shadow stack, follows once milestone 1 shows the
representation works; borrow from wallisp's engines/lisp_gc.c (shadow-stack
push/pop protocol, TRE notes) and engines/bytecode_gc.c (non-moving
mark-sweep, free-list sweep)."

Orientation done 2026-10-02 (nothing built):
- The backend keeps two post-MVP features under linear: exception handling
  (53 try_table/throw sites) and tail calls (21 return_call sites). The
  nooga/wazero fork noderati pins (0ec6142ae8c7) implements both behind
  `experimental.CoreFeaturesTailCall` / `CoreFeaturesExceptionHandling`;
  noderati sets no feature flags, so it runs wazero's default set. Either a
  one-line noderati change enables them, or the backend lowers try/throw
  and tail calls to MVP constructs. Default proposed: enable the flags.
- The runtime is plain lg through the same backend, so it follows the
  representation switch; the exceptions are the 22 raw-WAT intrinsics in
  rt/wasm/intrinsics.lg and the D11 host imports, which pass strings as GC
  array refs today. Linear strings are bytes in memory, so string-taking
  imports become ptr+len; proposed: node/browser hosts stay GC-only for
  milestone 1, the noderati host script is the only linear host.
- Ownership question: Matt also raised item 3 in the noderati session;
  proposed that this campaign takes all four items because the runner
  co-evolves with the host ABI.
- Default-path churn: the clean shape is a representation layer inside
  lower_wasm.lg that both targets emit through, which touches the WasmGC
  path and so needs gates 1-7 rerun before milestone 1 closes (an evening
  of background time). The alternative, a parallel emission path with
  duplicated op tables, is faster now and worse to keep.
- Assumptions to proceed on unless Matt objects: low bit 1 = fixnum, 0 =
  pointer; ints outside 31 bits boxed as heap $Int exactly as D41 boxes
  via ref.i31; header = type id + size; bump pointer in a global,
  memory.grow on demand, no free. Record as D170 when started; begin with
  the driver flag and the type-section switch.
