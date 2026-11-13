# Leaves as Direct Calls on llvm: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fns that never collect, never raise catchably and sit on no call-graph cycle compile on `--target llvm` to plain LLVM functions called directly, so LLVM can inline and optimize them.

**Architecture:** A classification pass marks leaf arities after analysis (program and runtime) by a fixpoint over the call graph and records `:leaf true` in each arity's signature. A leaf is emitted twice: `<name>.leaf`, one `fastcc` LLVM function (IR blocks as basic blocks, block params as phi nodes, `ret`), and its usual CPS entry reduced to a wrapper that calls `<name>.leaf` and returns to `%k`. Calls to a known leaf become direct `call fastcc`, with no continuation and no cut.

**Tech Stack:** let-go (lg) sources in src/, LLVM IR text, clang; checks are shell plus lg programs run through `checks/run.sh`.

**Spec:** docs/superpowers/specs/2026-11-06-llvm-direct-call-leaves-design.md

## Global Constraints

- llvm target only; the GC and linear lanes' output does not change (P8.0's byte guard and the GC rows stay green).
- Behavior is judged by `checks/oracle.sh` against native lg; never bytes or IR text, except where a check asserts a leaf's shape.
- A leaf never collects (no `ll-gc-check`), never raises catchably, and is on no call-graph cycle; it may allocate.
- Under `*trap-throws*` (--test), ops whose failure traps catchably (index checks, casts) are not leaf ops.
- No issue, row or decision ids in code or comments. Commits are Conventional Commits.
- Rows run through `checks/run.sh <id>` with `LW_ROOT` set; one heavy run at a time; `LW_SLOTS=1`.
- Corpus rules (corpus/README.md): one file per behavior, cases in the owning file; `checks/corpus-lint.sh` holds the budget.

## Review Focus

1. **A leaf used as a value** (passed to `map`, stored, applied): it must still work through its CPS wrapper. Test in Task 3.
2. **A var rebound at run time** (`def` again, `alter-var-root`, a var-table var): a call through it must stay CPS, never a direct call to the old leaf. Test in Task 4.
3. **Typed and boxed arguments across a direct call:** an `:int` param called with a boxed value, and a boxed result into an `:int` slot, coerce as the CPS path does. Test in Task 4.
4. **Multi-arity and variadic fns:** only fixed arities can be leaves; a variadic arity stays CPS, and other arities of the same fn are classified separately. Test in Task 1.
5. **Loops inside a leaf** (`loop`/`recur`, nested): the phi emission must carry every live value. Test in Task 3.

---

### Task 1: Classify leaves

**Files:**
- Create: `src/lower_llvm_leaf.lg` (namespace `lower-llvm-leaf`; required by `lower_llvm.lg`)
- Create: `checks/llvm-leaf-check.lg`, `checks/llvm-leaf-check.sh`
- Modify: `checks/items.tsv`, `checks/affected.sh` (row `LLVM.LEAVES`, as `LLVM.ORC` is laid out)
- Modify: `src/lower_llvm.lg`: rename the existing `ll-leaf-vars`/`ll-leaf-var?` (calls emitted inline without the runtime: `println`) to `ll-inline-vars`/`ll-inline-var?`, every use included, so "leaf" names only this plan's concept

**Interfaces:**
- Produces: `(leaf-op? f nid trap-throws?) -> boolean`: nid's op is on the allowlist (one table, `leaf-ops`, beside the fn).
- Produces: `(leaves infos sig-of) -> #{[var argc]}`: `infos` are analysed fn infos (`{:name :f :params :ret :var :argc}`), `sig-of` maps a callee var and argc to its arity sig or nil. Fixpoint from fns with no calls; a fn joins when every call reaches a known leaf of matching fixed arity; any fn on a call-graph cycle (self-calls included, other than `recur`) is excluded.

- [ ] **Step 0: Rename `ll-leaf-vars`/`ll-leaf-var?` to `ll-inline-vars`/`ll-inline-var?`** (no behavior change; `grep -n 'll-leaf-var' src/` finds nothing after).
- [ ] **Step 1: Write the failing check.** `checks/llvm-leaf-check.lg` builds IR (ir.build + the driver's pipeline, as the analysis path does) for these defns and asserts the classification:
  - leaves: `(defn r16 [b o] (bit-or (aget b o) (bit-shift-left (aget b (inc o)) 8)))`, `r32` calling `r16`, `r64` calling `r32`; `(defn sum-to [n] (loop [i 0 a 0] (if (< i n) (recur (inc i) (+ a i)) a)))` with `+` the wrapping op; a fn returning a fresh vector of its args (allocates).
  - not leaves: a fn using checked `+` on boxed values; a fn with `throw`; a fn with `try`; a fn returning a closure; `even?`/`odd?` defined mutually; a fn calling a non-leaf; a variadic arity (while its fixed arity is a leaf); `r16` when `trap-throws?` is true.
- [ ] **Step 2: Run it to see it fail.** `LW_ROOT=… checks/run.sh LLVM.LEAVES` → fails: `lower-llvm-leaf` not found.
- [ ] **Step 3: Implement `leaf-op?` and `leaves`** in `src/lower_llvm_leaf.lg`. Exclusions per the spec's Design section: any call `ll-call-plan*` would plan, checked arithmetic, integer div/rem whose zero case raises, `throw`, `try`, closures, dynamic var reads or bindings.
- [ ] **Step 4: Run it to see it pass.** `checks/run.sh LLVM.LEAVES` → `ok`.
- [ ] **Step 5: Commit.** `feat(llvm): classify leaf fns`

### Task 2: Record leafness in signatures

**Files:**
- Modify: `src/driver.lg` (after `analyze-program!`, before `lower-one`; and inside the boxing loop)
- Modify: `src/lower_wasm.lg` `build-rtlib!` (between the `rt-analyze!` pass and the `:pending` lowering loop), and the cached library's saved state so `:leaf` survives `load-rtlib!`
- Modify: `src/lower_llvm.lg` `ll-rtlib-key-extra` (the leaf source is part of the key)
- Test: `checks/llvm-leaf-check.lg`

**Interfaces:**
- Consumes: `lower-llvm-leaf/leaves`.
- Produces: `:leaf true` on `(get-in (q-sig v) [:arities argc])` for every leaf, program and runtime; `analysis-interfaces` carries it unchanged (it reads whole `q-sig`s).

- [ ] **Step 1: Add the failing assertions.** Compile a program defining `r16`/`r32`/`r64` with `--target llvm`; assert `(:leaf (get-in (lw/q-sig #'r64) [:arities 2]))` is true and false for the checked-`+` fn; after a restore of the cached runtime library, assert the same for `llvm.xxhash/mul-fold`'s arity 2.
- [ ] **Step 2: Run to see it fail.** `checks/run.sh LLVM.LEAVES` → the `:leaf` assertions fail.
- [ ] **Step 3: Call `leaves` at both points and `swap!` `:leaf true` into `lw/*sigs*`;** persist it with the runtime library; add `src/lower_llvm_leaf.lg` to `ll-rtlib-key-extra`'s sources.
- [ ] **Step 4: Run to see it pass;** also `checks/run.sh P13.1` (nothing calls leaves directly yet, so behavior is unchanged).
- [ ] **Step 5: Commit.** `feat(llvm): record leafness in signatures and the runtime library`

### Task 3: Emit a leaf as one direct-call function

**Files:**
- Modify: `src/lower_llvm.lg`: `llvm-fn` (a leaf also yields `<name>.leaf`), a new `ll-leaf-function!`, and `ll-label!` (records the current block label for phi incoming edges)
- Create: `corpus/llvm/leaves.lg` (the behavior file for leaves; no corpus file covers them)
- Test: `checks/llvm-leaf-check.lg` (IR shape), `corpus/llvm/leaves.lg` (behavior, under P13.3)

**Interfaces:**
- Consumes: `:leaf` on the arity sig (Task 2).
- Produces: `(ll-leaf-name sig) -> string`, `"<sig :name>.leaf"`; `(ll-leaf-function! info) -> items`: one `internal fastcc` function returning `(ll-type ret)`, params `(ll-type p)` per param, no `%k`, no `ll-gc-check`; every IR block a basic block `b<id>:`, block params as `phi` over `[value, label]` pairs gathered from each predecessor's edge at its current label; `:branch`/`:branch-if` as `br`; `:return` as `ret`. The CPS entry of a leaf becomes a wrapper: call `<name>.leaf`, then return its result to `%k` as `ll-return!` does.

- [ ] **Step 1: Write the failing cases.** `corpus/llvm/leaves.lg`: print `r64` over a 16-byte array; `sum-to` of 1000000; a leaf applied through `map`, stored in a vector and called from it (Review Focus 1); a nested loop leaf (Review Focus 5). In `checks/llvm-leaf-check.lg`, compile it with `--target llvm` and assert the module has `define internal fastcc i64 @"…r64.leaf"` whose body has no `lg_alloc` and no `musttail`.
- [ ] **Step 2: Run to see it fail.** `checks/run.sh LLVM.LEAVES` → no `.leaf` definition.
- [ ] **Step 3: Implement `ll-leaf-name`, `ll-leaf-function!` and the wrapper,** and have `llvm-fn` emit both for a leaf.
- [ ] **Step 4: Run to see it pass:** `checks/run.sh LLVM.LEAVES`, then `checks/run.sh P13.3` (the new file MATCHes, the rest unchanged).
- [ ] **Step 5: Commit.** `feat(llvm): emit leaves as direct-call functions`

### Task 4: Call leaves directly

**Files:**
- Modify: `src/lower_llvm.lg`: `ll-call-plan*` (no plan for a call to a known leaf), and the `:call` arm of the instruction dispatch (a new `ll-leaf-call!`)
- Test: `corpus/llvm/leaves.lg`, `checks/llvm-leaf-check.lg`

**Interfaces:**
- Consumes: `ll-leaf-name`, `:leaf` sigs.
- Produces: `(ll-leaf-call? nid) -> boolean`: a `:call` whose callee resolves to a var that is not a table var, not rooted, and whose arity sig for this argc has `:leaf true`. `(ll-leaf-call! nid)`: `call fastcc <ret> @"<leaf>"(args coerced as ll-arg does)`, the result bound with `ll-bind!`.

- [ ] **Step 1: Add the failing cases** to `corpus/llvm/leaves.lg`: a CPS fn calling `r64` in a loop of 1000000 iterations (constant C stack); the checked-`+` fn raising inside `try` and caught; an `:int` param leaf called with a boxed value and its result stored in a vector (Review Focus 3); a leaf var redefined with `def` and called after, printing the new result (Review Focus 2). In the check, assert the caller's IR calls `r64.leaf` with `call fastcc` and allocates no frame for it.
- [ ] **Step 2: Run to see it fail.** `checks/run.sh LLVM.LEAVES` → the caller still emits `musttail` to `r64`.
- [ ] **Step 3: Implement `ll-leaf-call?` and `ll-leaf-call!`;** in `ll-call-plan*`, return nil for a leaf call so `ll-cuts` makes no cut.
- [ ] **Step 4: Run to see it pass:** `checks/run.sh LLVM.LEAVES`, `checks/run.sh P13.3`, `checks/run.sh P13.1`, `checks/run.sh P12.37`.
- [ ] **Step 5: Commit.** `feat(llvm): call leaves directly`

### Task 5: Measure and verify

**Files:**
- Create: `checks/llvm-xxh3-bench.sh` (hyperfine over a program hashing a 25 MB file with `xxh3/HashString`, under `checks/quiet.sh`)
- Modify: `docs/superpowers/specs/2026-11-06-llvm-direct-call-leaves-design.md` (a Results section)

- [ ] **Step 1: Record the before number** at the commit before Task 1: `bash checks/llvm-xxh3-bench.sh` (expected about 2.9 s at 25 MB).
- [ ] **Step 2: Record the after number** at the head; the target is under 100 ms, recorded, not gating.
- [ ] **Step 3: Full row run** of llvm-parity's 121-row set on a quiet machine with `caffeinate`; every row passes, including the llvm benchmark rows, none slower.
- [ ] **Step 4: Write both numbers and the run's result** into the design's Results section.
- [ ] **Step 5: Commit.** `docs(llvm): record the leaves measurements`
