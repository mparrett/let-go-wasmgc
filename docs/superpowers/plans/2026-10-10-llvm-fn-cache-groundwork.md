# Function cache, plan 1 of 3: groundwork (no cache yet) — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every input to lowering a function explicit and recorded, and build the De Bruijn form normalizer the cache keys on:
the session questions it asks, and the compiler functions it runs. Then
make type ids safe to reuse across compiles, and measure the cost floor
that sets the cache's speed bound.

**Architecture:**
- A new namespace, `lower-llvm-cache` (`src/lower_llvm_cache.lg`), holds a
  trace recorder: `ask`, `ran!` and `with-trace`. It has no driver, file or
  session dependency, so an in-image compiler can use it later.
- Every lowering-time read of session state moves into a `defquestion`
  defined next to the state it reads. A lint, which reads source forms and
  does no regex over text, keeps it that way.
- Under `--target llvm`, the analysis and lowering of each function run
  inside `with-trace`, and wrappers on the compiler's vars record which
  compiler functions ran.
- Program and environment type ids become `lg_tid.<type>` constants,
  which module assembly assigns.

**Tech stack:** let-go (lg pinned at ff1e6dac, `checks/env.sh`'s `$LG`),
LLVM IR text, bash checks, hyperfine.

**Spec:** `docs/superpowers/specs/2026-10-10-llvm-fn-cache-design.md`
(the "Delivery" plan 1). Read it first, especially "Where this is going",
"Model", "Names stay valid across compiles" and "Recording every lookup".

## Global constraints

- **Branch `llvm-poly`.** Commits have no Claude attribution (a hook
  enforces this) and no SHAs in messages. Use `LW_PAR=1` for gate runs.
  Keep the let-go pin at ff1e6dac.
- **Acceptance is behavior, never bytes.** The gate runner is
  `LW_PAR=1 checks/llvm-behavior-gates.sh`, and all of its rows must pass
  at the end of every task.
- **No gensyms at load.** Code added to any file that the GC lane loads
  (`lower_wasm.lg`, `lw_rt.lg`, `lw_ext.lg`, `lower_llvm_cache.lg`) uses no
  destructuring, no `for`, and no syntax-quote auto-gensyms (`x#`).
  `#()` is fine (D196). Check with `checks/gensym-load.sh`: it reads
  **1133** at the start of this plan, against a recorded 1130. That drift
  is pre-existing and not ours. The number must stay 1133 after each task.
- **No GC-lane change.** The GC lane records nothing: `ask` outside a
  trace just returns the answer, and no wrappers are installed unless
  `*target*` is `:llvm`. The gate runner's GC rows (gc-corpora, P7.0,
  P7.11) must pass.
- **No file I/O in `lower-llvm-cache`.** No `slurp`, `spit` or `os/*`
  there; storage belongs to plan 2.
- **No session atom read from lowering code** except inside a
  `defquestion`, or in a function on the lint's assembly allowlist (each
  entry has a comment saying why).
- **New check rows go in `checks/llvm-behavior-gates.sh`** and in
  `checks/affected.sh`, with the next free ids: P12.40 (funnel) and P12.41
  (traces).

## Review focus

1. **A question whose answer holds a var, an atom or a fn.** It must hash
   the same in every compile, using names for vars, or throw "unhashable
   answer" for an atom or a fn. It must never hash an identity. Task 1
   tests this.
2. **The same question asked twice in one function with different
   answers** (state mutated mid-lowering). The trace marks it
   `:unstable` rather than keeping either answer. Task 1 tests this.
3. **Nested builds:** a callee analysed while its caller is being lowered
   records its questions and compiler functions in its own trace, never
   the caller's. The caller records only that it asked for the callee's
   signature. Tasks 1 and 5 test this.
4. **A compiler function called only through a higher-order path** (passed
   to `map` or `reduce`) is still recorded as having run. Task 5 tests
   this.
5. **A lazy answer** (a seq produced by a session read) is realized before
   it is hashed, so the hash matches what lowering consumed. Task 1 tests
   this.

---

### Task 1: the trace recorder

**Files:**
- Create: `src/lower_llvm_cache.lg`
- Test: `corpus/llvm-rt/llvm_cache_test.lg` (run by row P12.23)

**Interfaces:**
- Produces, in ns `lower-llvm-cache`:
  - `(ask q f)`: calls `f` (0-arg) and returns its answer. Inside a trace
    it records `q -> (answer-hash answer)`. `q` is a vector whose head is
    a keyword, such as `[:sig #'user/f]`.
  - `(ran! sym h)`: inside a trace, records that compiler function `sym`
    (a qualified symbol) with source hash `h` (a string) ran. Outside a
    trace it does nothing.
  - `(with-trace f)`: returns `[value trace]`. `trace` is
    `{:asks {q-enc hash-or-:unstable} :ran {sym h}}`, where `q-enc` is `q`
    passed through `encode`. `value` is realized in full, like
    `lower-llvm-ir/with-refs`.
  - `(encode x)`: canonical data. A var becomes `[:lw/var "ns/name"]`,
    maps and sets become sorted vectors of their encoded entries (sorted
    by `pr-str`), and seqs are realized. An atom, fn or volatile throws
    `ex-info "lower-llvm-cache: unhashable answer"`.
  - `(answer-hash x)`: `(format "%016x" (hash/xxh3-64-str (pr-str (encode x))))`.
  - `(defquestion name [args] q-expr answer-expr)`, a macro: defines `name`
    as `(fn [args] (ask q-expr (fn [] answer-expr)))`, with no gensyms.
  - `(normalize form resolve)`: the expanded `form`, with each binder
    replaced by `:lw/bind` (a param vector becomes a vector of them) and
    every use of a local replaced by its De Bruijn index `[:lw/local n]`. `n` counts the
    binders between the use and the local it names, innermost 0. Every
    other symbol becomes `(resolve sym)`, the caller's resolution: a var as
    `[:lw/var "ns/name"]`, a class by name, a special form as itself. It
    takes no gensyms and reads no session. The form hash, used in plan 2,
    is `(answer-hash (normalize form resolve))`.
    - **The binders are the expanded special forms:** `fn*` (its name,
      then each arity's params, in order, `&` skipped), `let*` and `loop*`
      (each binding, in sequence, so a later init sees the earlier names),
      `letfn*` (all names bound before any fn body), and `catch` (its
      local).
    - **Left alone:** `quote` and the head of `.`/`new` forms keep their
      contents; a keyword or literal stays as it is.

- [ ] **Step 1: Write the failing tests** in `corpus/llvm-rt/llvm_cache_test.lg`
  (ns `llvm-cache-test`, requiring `[lower-llvm-cache :as lc]`):

```clojure
(deftest ask-records-inside-a-trace-only
  (is (= 3 (lc/ask [:k 1] (fn [] 3))) "outside a trace: just the answer")
  (let [[v t] (lc/with-trace #(lc/ask [:k 1] (fn [] {:a 1})))]
    (is (= {:a 1} v))
    (is (= {[:k 1] (lc/answer-hash {:a 1})} (:asks t)))))

(deftest answers-hash-canonically
  (is (= (lc/answer-hash {:a 1 :b 2}) (lc/answer-hash (assoc {:b 2} :a 1))))
  (is (= (lc/answer-hash #{1 2 3}) (lc/answer-hash (conj #{3 2} 1))))
  (is (= [:lw/var "clojure.core/inc"] (lc/encode #'inc)))
  (is (= (lc/answer-hash (map inc [1 2])) (lc/answer-hash [2 3])) "a lazy answer is realized")
  (is (thrown? Exception (lc/answer-hash (atom 1))))
  (is (thrown? Exception (lc/answer-hash inc))))

(deftest a-changed-answer-is-unstable
  (let [a (atom 1)
        [_ t] (lc/with-trace #(do (lc/ask [:x] (fn [] @a)) (reset! a 2) (lc/ask [:x] (fn [] @a))))]
    (is (= :unstable (get (:asks t) [:x])))))

(deftest nested-traces-are-separate
  (let [inner (atom nil)
        [_ outer] (lc/with-trace
                    (fn [] (lc/ask [:outer] (fn [] 1)) (lc/ran! 'lower-wasm/a "h1")
                      (reset! inner (second (lc/with-trace #(do (lc/ask [:inner] (fn [] 2)) (lc/ran! 'lower-wasm/b "h2")))))))]
    (is (= #{[:outer]} (set (keys (:asks outer)))))
    (is (= {'lower-wasm/a "h1"} (:ran outer)))
    (is (= #{[:inner]} (set (keys (:asks @inner)))))
    (is (= {'lower-wasm/b "h2"} (:ran @inner)))))

(defn- res [s] (if-let [v (resolve s)] (lc/encode v) s))
(defn- fh [form] (lc/answer-hash (lc/normalize form res)))

(deftest renamed-locals-hash-equal
  (is (= (fh '(fn* ([x] (let* [y (inc x)] (+ x y)))))
         (fh '(fn* ([a__12] (let* [b__99 (inc a__12)] (+ a__12 b__99))))))))

(deftest indices-count-binders-outward
  (is (= '(fn* ([:lw/bind] (let* [:lw/bind [:lw/local 0]] [:lw/local 1])))
         (lc/normalize '(fn* ([x] (let* [y x] x))) res))
      "x is 0 in y's init (not yet under y), 1 in the let's body")
  (is (not= (fh '(fn* ([x] (fn* ([y] x))))) (fh '(fn* ([x] (fn* ([y] y))))))
      "which binder a use names is kept"))

(deftest a-subform-hashes-the-same-in-any-context
  ;; De Bruijn indices, not binding order: a closed inner fn is independent
  ;; of how many locals its parent binds before it
  (let [inner '(fn* ([z] (inc z)))]
    (is (= (fh inner)
           (fh (nth (lc/normalize (list 'let* '[a 1 b 2] inner) res) 2))
           (fh (nth (lc/normalize (list 'let* '[c 3] inner) res) 2))))))

(deftest shadowing-letfn-loop-catch
  (is (= (fh '(let* [x 1 x (inc x)] x)) (fh '(let* [p 1 q (inc p)] q))) "a later binding shadows")
  (is (= (fh '(letfn* [f (fn* f ([n] (g n))) g (fn* g ([m] (f m)))] (f 1)))
         (fh '(letfn* [h (fn* h ([n] (k n))) k (fn* k ([m] (h m)))] (h 1)))))
  (is (= (fh '(loop* [i 0] (recur (inc i)))) (fh '(loop* [j 0] (recur (inc j))))))
  (is (= (fh '(try (f) (catch Exception e e))) (fh '(try (f) (catch Exception e2 e2))))))

(deftest free-vars-and-quotes-keep-their-names
  (is (not= (fh '(fn* ([x] (inc x)))) (fh '(fn* ([x] (dec x))))) "a free var is its qualified name")
  (is (not= (fh '(quote x)) (fh '(quote y))) "quoted symbols are data, not locals"))

(lc/defquestion q-double [n] [:double n] (* 2 n))
(deftest defquestion-asks
  (let [[v t] (lc/with-trace #(q-double 4))]
    (is (= 8 v))
    (is (contains? (:asks t) [:double 4]))))
```

- [ ] **Step 2: Run it and watch it fail.**
  Run: `TEST_DIR=corpus/llvm-rt checks/run-intrinsics-native.sh 2>&1 | tail -5`
  Expected: `llvm_cache_test` fails on a missing namespace `lower-llvm-cache`.
- [ ] **Step 3: Implement `src/lower_llvm_cache.lg`** to the interfaces
  above. Its ns docstring states the rules: no file I/O, and no gensyms at
  load (Global constraints). The trace is a dynamic var holding an atom,
  bound by `with-trace`, the same shape as `lower-llvm-ir/*refs*`.
- [ ] **Step 4: Run it and watch it pass.** Same command. Expected: every
  file passes, `llvm_cache_test` included, and `checks/gensym-load.sh`
  still reads 1133. The namespace isn't loaded by the GC lane yet; Task 3
  makes it so.
- [ ] **Step 5: Commit** `src/lower_llvm_cache.lg` and
  `corpus/llvm-rt/llvm_cache_test.lg`, with the message
  "llvm target: a trace recorder for lowering's inputs".

### Task 2: the funnel lint

**Files:**
- Create: `checks/llvm-funnel-lint.lg`, and `checks/llvm-funnel-check.sh`
  (row P12.40)
- Modify: `checks/llvm-behavior-gates.sh`, `checks/affected.sh`

**Interfaces:**
- Produces: `checks/llvm-funnel-check.sh`. It runs the lint over
  `src/lower_wasm.lg`, `src/lower_llvm.lg`, `src/lower_llvm_rt.lg`,
  `src/lower_llvm_poly.lg`, `src/lw_rt.lg` and `src/lw_ext.lg`. For each
  violation it prints `funnel: <file> <defn> reads <sym>`, then
  `llvm-funnel: N violations`, and exits 1 when N > 0.
- **The lint's rule.** It reads each file's top-level forms with the
  reader, not with regexes. A *violation* is an occurrence of one of the
  session input symbols inside a top-level `defn`/`defn-` whose name is
  not on the assembly allowlist, except in these places:
  - inside a `defquestion` form;
  - as the target of `swap!` or `reset!` (a write, which is an output);
  - as a key in a `binding` vector.

  The session input symbols are `*sigs*`, `*rt*`, `*prog-decls*`,
  `*var-globals*`, `*rooted-natives*`, `*thunk-def-vars*`,
  `*program-file*`, `*box-params*`, `*stub-libs*`, `*externs*`,
  `*fn-values*`, `lib-defns` and `stdlib-index`.
- **The assembly allowlist** is a set in the lint, one comment per entry.
  It starts as: `new-session`, `with-session*`, `add-decl!`,
  `session-module`, `module-parts`, `rt-fixpoint`, `build-rtlib!`,
  `rtlib-snapshot`, `rtlib-restore!`, `load-rtlib!`, `llvm-module`,
  `ll-live`, `ll-rtlib-snapshot`, `ll-rtlib-restore!`. A function belongs
  there only if it runs once per compile, not once per lowered function.
  Note who calls it in its comment.

- [ ] **Step 1: Write the lint and the check.** Plant a violation to test
  the lint itself: a temp copy of a tiny file with
  `(defn f [v] (get @*sigs* v))` is reported, and the same read wrapped in
  a `defquestion` is not. The check script runs this self-test first.
- [ ] **Step 2: Run it and watch it fail.**
  Run: `checks/llvm-funnel-check.sh | tail -3`
  Expected: the self-test passes, then many violations, and exit 1.
  Record the count, about 100, in the ledger.
- [ ] **Step 3: Wire it in.** Add row P12.40 to the gate runner,
  commented "fails until Task 4", and to `checks/affected.sh` with
  inputs `src/ checks/llvm-funnel-lint.lg checks/llvm-funnel-check.sh`.
- [ ] **Step 4: Commit** with the message "llvm target: a lint for
  lowering's session reads (P12.40)". The gate stays red on P12.40 until
  Task 4. Ledger that as a ruling.

### Task 3: questions in `lower_wasm.lg`

**Files:**
- Modify: `src/lower_wasm.lg` (requires `[lower-llvm-cache :as lc]`)

**Interfaces:**
- Produces questions, each a `defquestion` placed beside the state it
  reads, named `q-<what>`:
  - `q-sig [v]`: `[:sig v]`, `(get @*sigs* v)`
  - `q-rt-state [v]`: `[:rt-state v]`
  - `q-rt-global [v]`: `[:rt-global v]`
  - `q-var-global [v]`: `[:var-global v]`
  - `q-prog-decl [v]`: `[:prog-decl v]`
  - `q-rooted? [v]`: `[:rooted v]`
  - `q-thunk-def? [v]`: `[:thunk-def v]`
  - `q-program-file []`: `[:program-file]`
  - `q-box-params []`: `[:box-params]`
  - `q-stub-libs []`: `[:stub-libs]`
  - `q-extern [v]`: `[:extern v]`
  - `q-fn-value [k]`: `[:fn-value k]`

  A read with no question on this list gets its own `q-<what>`, added
  here and in the ledger.
- **Rule for memos.** A read of a memo whose content is a pure function of
  its key and of answers already recorded is still a question. For
  example, `*fn-values*` `[:llvm v sig]` holds a content-named symbol. It
  costs nothing, and it keeps the rule simple: every read is asked.

- [ ] **Step 1: Run the lint for this file.**
  Run: `checks/llvm-funnel-check.sh | grep lower_wasm`. That list is the
  task.
- [ ] **Step 2: Replace each reported read with its question.** Keep the
  defquestions free of gensyms (Global constraints).
- [ ] **Step 3: Verify.** The lint reports no `lower_wasm.lg` lines;
  `checks/gensym-load.sh` reads 1133; and
  `LW_PAR=1 checks/llvm-behavior-gates.sh` passes every row but P12.40.
- [ ] **Step 4: Commit** with the message "lower-wasm: lowering reads the
  session through questions".

### Task 4: questions in the llvm files and `lw_rt`/`lw_ext`

**Files:**
- Modify: `src/lower_llvm.lg`, `src/lower_llvm_rt.lg`,
  `src/lower_llvm_poly.lg`, `src/lw_rt.lg`, `src/lw_ext.lg`

**Interfaces:**
- Consumes: Task 3's questions.
- Produces, in `lw-rt`:
  - `q-source-defn [v]`: `[:source-defn v]`
  - `q-rt-target [v]`: `[:rt-target v]`
  - `q-stdlib-twin [v]`: `[:stdlib-twin v]`
  - `q-stdlib-alias [v]`: `[:stdlib-alias v]`

  These wrap the existing functions; their callers in lowering code
  switch to the questions. `lw-rt` requires `lower-llvm-cache`, which
  depends on nothing in the compiler, so this adds no cycle.

- [ ] **Step 1: Run the lint.** Its remaining lines are the task.
- [ ] **Step 2: Replace each read with its question.**
- [ ] **Step 3: Verify.** `checks/llvm-funnel-check.sh` prints
  `llvm-funnel: 0 violations` and exits 0; gensym-load reads 1133; and
  every gate row passes, P12.40 included.
- [ ] **Step 4: Commit** with the message "llvm target: every lowering
  read is a question (P12.40 green)".

### Task 5: a trace per lowered function, and the compiler functions it ran

**Files:**
- Modify: `src/lower_wasm.lg` (`rt-analyze*!`, `lower-pending!`,
  `analyze-fn`, `lower-fn`, new-session's atoms),
  `src/lower_llvm_cache.lg` (wrappers), `src/driver.lg` (the dump)
- Create: `checks/fixtures/trace-probe.lg`, `checks/llvm-trace-check.sh`
  (row P12.41), `checks/llvm-trace-check.lg`

**Interfaces:**
- Consumes: `lc/with-trace`, `lc/ran!`, Task 3's and Task 4's questions.
- Produces:
  - **The traces.** Under `:llvm`, the session holds `*traces*`, an atom
    mapping a function's lowered name (its `:name`, as `lower-pending!`
    keys `:lowered`) to its trace. A function's trace is the merge of the
    trace of its analysis and the trace of its lowering. A nested
    analysis gets its own trace.
  - **`(lc/install-code-tracing! nss)`.** It wraps every function-valued,
    non-macro var interned in namespaces `nss` with
    `(fn [& args] (ran! sym h) (apply f args))`, where `h` is the xxh3 of
    `pr-str` of the var's top-level source form. Forms are read from the
    namespace's source file, and the caller passes in the file.
    - It is called once, when `--target llvm` loads, with `lower-wasm`,
      `lower-llvm`, `lower-llvm-rt`, `lower-llvm-ir`, `lower-llvm-poly`,
      `lower-llvm-profile`, `lw-rt` and `lw-ext`, and never on `:gc`.
    - It skips `lower-llvm-cache` itself, and the functions `with-trace`
      calls.
    - Its file reading happens in the caller (`lower_llvm.lg`'s loader),
      not in `lower-llvm-cache`, which keeps that namespace's no-I/O rule.
  - **The dump.** `LW_LL_TRACES=<path>` makes the driver write `@*traces*`,
    passed through `lc/encode`, as EDN at the end of an llvm compile.
- **The probe program**, `checks/fixtures/trace-probe.lg`:

```clojure
(defn sq [x] (* x x))
(defn twice [f x] (f (f x)))
(def base 3)
(defn run [] (twice sq base))
(println (run) (map inc [1 2]))
```

- [ ] **Step 1: Write the failing check.** `checks/llvm-trace-check.sh`
  compiles the probe with `LW_LL_TRACES`, then runs
  `checks/llvm-trace-check.lg` on the dump. It asserts that:
  1. every lowered program function (`sq`, `twice`, `run`, `_main`) has a
     trace;
  2. `run`'s `:asks` holds a `:sig` question for `user/twice` and a
     `:var-global` question for `user/base`;
  3. `run`'s `:asks` holds none of `twice`'s own questions (nesting);
  4. `run`'s `:ran` names `lower-wasm/lower-fn`, and `_main`'s `:ran`
     names a compiler function reached only through `map` or `reduce` in
     the lowering of a call (pick one, and name it in the check's
     comment);
  5. every `:ran` hash equals the xxh3 of that function's source form,
     recomputed by the check from the source file.

  It prints `llvm-traces: OK` or the first failed assertion.
- [ ] **Step 2: Run it and watch it fail.** Expected: no dump written
  (`LW_LL_TRACES` isn't implemented).
- [ ] **Step 3: Implement** the trace binding, the wrappers and the dump.
- [ ] **Step 4: Verify.** The check prints `llvm-traces: OK`;
  gensym-load reads 1133; every gate row passes; and xsofy's row P12.38
  is still 20/20.
- [ ] **Step 5: Measure the wrappers' cost.** Run
  `hyperfine -w1 -r3` on an llvm compile of `corpus/poly/types.lg` with
  `--no-rtlib`, with and without the wrappers. Expose the toggle
  `LW_LL_NO_CODE_TRACE=1` for this measurement only. Ledger both means.
  If the cost passes 25% of the compile, stop and bring the numbers to the
  user before plan 2. It stays in, but it is a design input for plan 2.
- [ ] **Step 6: Commit and wire in.** Add row P12.41 to the gate runner
  and to `affected.sh`. Commit with the message "llvm target: a trace per
  lowered function, with the compiler functions it ran (P12.41)".

### Task 6: type ids as constants, and the gensym audit

**Files:**
- Modify: `src/lower_llvm_rt.lg` (`ll-next-id!`, `ll-prog-types`,
  `ll-env-tid!`, `ll-tid`, `ll-alloc!`'s callers), `src/lower_llvm.lg`
  (`llvm-module` emits the constants)
- Test: `corpus/llvm/tid-order.lg` (with its `.lg.out` from native lg)

**Interfaces:**
- Produces:
  - **`(ll-tid-op! tn)`.** It gives the operand that stores type `tn`'s id
    in an instruction.
    - A static type (a runtime decl, `$FnV`, `$FnX`) keeps its literal
      id, as today.
    - A program type or an environment type gets a register: the step
      emits `%t = load i64, ptr <ref "lg_tid.<T name>">`, recording the
      ref, and returns `%t`. The T name is the type operand's name, such
      as `T.prog.Point` or `Env.bb`.
  - **Id assignment moves to module assembly.** `llvm-module` gives
    program types and environments their ids there, in order of type
    name, after the static types. It emits
    `@"lg_tid.<name>" = internal constant i64 <id>` for each type the
    kept units name. The type table (D218) uses the same assignment.
  - `ll-next-id!`'s first-use counter goes away.

- [ ] **Step 1: Write the failing test** `corpus/llvm/tid-order.lg`. It
  has two namespaces' worth of closures with different capture kinds
  (`[:box]`, `[:int :box]`, `[:float]`), created in opposite orders in two
  functions; a `deftype` instance; and `(type x)` / `instance?` on each.
  Generate its `.lg.out` with native lg. The test asserts behavior only.
  Also add a unit assertion to `corpus/llvm-rt/llvm_ir_test.lg`, if
  `ll-tid-op!` can run there without a session. If it can't, ledger that
  and rely on P12.39's refs check, which fails if a `lg_tid.` ref goes
  unrecorded.
- [ ] **Step 2: Check that it currently passes.** It should: today's
  numbering is correct within one compile. So this step is a guard, not a
  red test. The red signal for this task is Step 4's audit: before the
  change, `rg -n 'll-tid' src/lower_llvm*.lg` lists the instruction sites
  that store a counter-assigned id as a literal. Record them.
- [ ] **Step 3: Implement** `ll-tid-op!` and the assembly-time assignment.
  Switch every instruction site from Step 2's list to `ll-tid-op!`. A
  global initializer that names a program or environment id becomes a
  reference to the constant. The spec expects none; ledger any you find.
- [ ] **Step 4: Gensym audit.** List every place a module symbol is
  built: `lir/ref` and `ref-bare` callers, and `ll-glob`, `ll-fn` and
  `ll-declare` names. Confirm that none derives from `gensym`. Ledger the
  list and the result. Fix any that does, by naming it from content.
- [ ] **Step 5: Verify.** `tid-order.lg` MATCHes on P12.3a's corpus; P12.39
  (refs) passes; and every gate row passes.
- [ ] **Step 6: Commit** with the message "llvm target: program and
  environment type ids are constants named for the type".

### Task 7: the cost floor, and the speed bound

**Files:**
- Modify: `docs/superpowers/specs/2026-10-10-llvm-fn-cache-design.md`
  (the Speed bullet), `DECISIONS.md` (D226)
- Uses: `checks/compile-times.sh` (not a gate row), built for 7be2318.
  There is no separate `checks/llvm-phase-times.sh`.

**Interfaces:**
- Produces: `LW_PHASE_TIMES=1`, which makes the driver print
  `phase <name> <ms>` lines to stderr for these phases:
  - `read` (reading the program file; its libraries are read during
    `load`, inside `load-libs!`);
  - `load` (native loading of the program and its libraries, indexing and
    expansion);
  - `rtlib` (restoring the snapshot);
  - `analyze+lower`;
  - `assemble` (`llvm-module`);
  - `write`.

  `checks/compile-times.sh` warms the runtime cache, compiles each
  program N times with the flag, and prints each run, each phase's median
  and the llvm/gc wall ratio. Task 7 runs it as
  `checks/quiet.sh checks/compile-times.sh --runs 3 --targets llvm
  --source-paths $XSOFY corpus/dump-world.lg` (medians of 3, not means),
  then times clang on the compiled `.ll` with `hyperfine -w1 -r3`; the
  script does not time clang.

- [x] **Step 1: Implement the flag and the script.** Done on branch
  `llvm-phase-times` (69e2221), for 7be2318; the gensym count after load
  is unchanged (1133).
- [ ] **Step 2: Measure.** Run the script against a warm runtime snapshot.
  7be2318's numbers (ndn.local, medians of 5) are a starting point:
  world dump analyze+lower 14.97 s, assemble 46.45 s, rtlib 3.51 s.
  The `rtlib` phase (restoring the runtime snapshot) is part of the
  bound, as are assemble's shake and text (time them inside `assemble`).
  From one LW_LL_TRACES dump of the same compile, also take:
  - the total number of questions across all traces;
  - the time to re-ask them all (a loop in `checks/llvm-trace-check.lg`'s
    style, timed);
  - the time to compute every function's form hash
    (`lc/normalize`, then `answer-hash`, over its expanded form).
- [ ] **Step 3: Write the bound.** Replace the spec's Speed bullet's "is
  set after measuring" text with the measured numbers, their sum, and the
  bound: the sum plus 50%, rounded up to a whole second. Write D226 in
  `DECISIONS.md`. It covers:
  - what plan 1 built (the funnel, the code tracing, the tid constants);
  - P12.40 and P12.41;
  - the wrapper cost, the phase times and the bound;
  - P9.1's pre-existing drift (1133 against a recorded 1130), noted
    rather than fixed.
- [ ] **Step 4: Verify.** Every gate row passes
  (`LW_PAR=1 checks/llvm-behavior-gates.sh`).
- [ ] **Step 5: Commit** `DECISIONS.md` and the scripts. The spec is
  git-ignored, so it stays on disk. Message: "llvm target: phase times
  and the function cache's speed bound (D226)".
