# Property harness for IR lowerings

Status: design, 2026-10-09. Replaces byte-identity guards (P8.0,
checks/gc-byte-identity.sh) with properties. Approved in conversation; this
is the written form for review.

## Goal

A property harness you point at an IR lowering. It generates programs,
runs them through that lowering, and checks two kinds of claim:

- **Behavior:** the lowering's program does what native lg does. These are
  equalities against an oracle.
- **Expectations:** the lowering stays within a bound. These are
  inequalities (≤), such as size, time, heap, stack or gensym counts,
  against a stated limit or against another lowering.

A failure gives the seed and a shrunk minimal counterexample (let-go's
`check`: `for-all`, generators as rose trees, greedy shrinking). The
harness runs under native lg, as rows in `checks/items.tsv`.

## Non-goals (for now)

- Formal proof. "Theory" here means quantified properties checked over
  generated inputs, with shrinking, not a proof assistant.
- Generating IR directly. Programs are generated as source and reach the
  lowering through the driver's analysis, so every IR the harness feeds a
  lowering is one the front end can produce. An IR-level generator is
  possible later on the same adapter.

## 1. The lowering adapter

A lowering under test is a map. The harness knows nothing else about it:

```clojure
{:id       :gc                      ; a name for reports
 :compile  (fn [src-path opts] ...) ; -> {:artifact path :log text} or {:error text}
 :run      (fn [artifact args] ...) ; -> {:out text :err text :exit n}
 :measure  (fn [artifact] ...)      ; -> {:bytes n :funcs n ...}, lowering-defined keys
 :fn-lower (fn [ir-fn-info] ...)}   ; optional: one IR fn alone (lower-fn-only), -> {:text :externs}
```

- `checks/props/lowerings.lg` defines the adapters for `:gc`, `:linear`
  and `:llvm` over the existing driver flag (`--target`) and runners
  (`checks/wasm-run.sh`, `checks/wasm-run-linear.sh`,
  `checks/native-run.sh`). A new lowering adds one map.
- `:oracle` is native lg, an adapter with `:run` and no `:compile`.
- `:fn-lower` uses the census seam (`lower-wasm/lower-fn-only`), so a
  property can quantify over single IR functions without a whole module.

## 2. Properties

A property names the lowerings it takes and returns pass/fail with a
reason. `checks/props/props.lg` defines them with `defprop` over a
generator from section 3. Kinds:

- **Equivalence** (behavior), on one lowering L:
  - `matches-oracle`: for all p, `run(L, p)` = `run(oracle, p)` on stdout
    and exit code, with error text normalized as `checks/oracle.sh` does.
  - `deterministic`: for all p, compiling p twice (with a fresh runtime
    cache, then a warm one) gives the same artifact. This catches D173's
    class of bug.
- **Non-interference**, on L and a second lowering M:
  - for all p, L's artifact for p is the same whether or not M's code was
    loaded earlier in the same process. A GC build also never loads
    `lower-llvm-*` or `lower-linear`.
  - This is what the byte guard really claims, computed in-process with
    no pinned commit.
- **Expectations** (inequalities):
  - `size-bound`: for all p, `measure(L,p).bytes` ≤ `k × measure(R,p).bytes`
    against a reference lowering R. An absolute ceiling is also allowed.
  - `time-bound`: for all p in a cost-bearing generator, L's run time is
    ≤ `c ×` the oracle's, with a floor for noise. It is checked over the
    median of n runs.
  - `heap-bound` (llvm): peak heap is ≤ a stated budget for generated
    programs whose live data is bounded (`LG_HEAP_BYTES`, D215).
  - `stack-bound`: a generated self- or mutual tail-recursion of depth N
    runs without growing the native stack (every call is musttail, D206).
  - `gensym-bound`: the gensym counter after the driver loads is ≤ the
    recorded EXPECT. P9.1 already pins this exactly; here it becomes ≤,
    so a change that frees gensyms passes.
- **Laws** of runtime parts, quantified natively, with no compile:
  - C3: for random consistent graphs, the linearization starts with the
    type, holds each ancestor exactly once, keeps local precedence order,
    and is monotonic (each parent's linearization is a subsequence). For
    inconsistent graphs it raises the C3 error.
  - Reader: for any namespace n and name k, `::k` after `(ns n)` or
    `(in-ns 'n)` reads as `:n/k`, and each form's `:line` matches native's.
  - Hierarchy: for random `derive`/`underive` sequences, `isa?` is
    reflexive and transitive, `ancestors` is the transitive closure of
    `parents`, `descendants` is its inverse, and `underive` undoes a
    `derive`. On llvm this is checked through `matches-oracle` with the
    hierarchy generator.

A bound's constants (`k`, `c`, budgets) live in `checks/props/bounds.edn`
with the reason for each. A change that needs a looser bound edits that
file and says why in its DECISIONS entry. This replaces re-pinning.

## 3. Generators

`checks/props/gen.lg`, built on `check`'s `gen-int`, `gen-elements`,
`gen-vector`, `fmap`, `bind` and `gen-frequency`:

- `gen-value`: nil, bools, ints at the fixnum and i31 edges, floats
  (including -0.0, NaN and ±Inf), strings with escapes and multi-byte
  text, chars, keywords and symbols with and without a namespace, `::k`,
  and nested vectors, maps, sets and lists.
- `gen-expr`: depth-bounded expressions over `let`, `if`, `do`, `fn`
  (fixed and variadic arities), calls of a whitelisted set of core fns
  (arithmetic, comparison, collection and seq ops), `try`/`catch`/`throw`
  and `loop`/`recur`.
- `gen-program`: an optional `(ns ...)` header, `in-ns` switches,
  top-level `def`/`defn`, and a body that prints each result with `prn`.
  Its well-formedness is generator-side: names are bound before use, and
  arities match.
- Feature generators for later tasks plug in here: protocols, deftype and
  defrecord, multimethods with hierarchies.
- Shrinking comes from the rose trees: smaller depth, fewer forms, smaller
  literals.

Programs whose oracle run hits a known, recorded divergence (spec
divergences, DECISIONS entries) are filtered by a predicate in
`gen.lg` that names the divergence, so a property never passes by
silently skipping.

## 4. Runner and rows

- `checks/run-props.sh <prop-ns>/<prop> [--lowering L] [--seed S] [--n N]`
  runs one property, or every property in a file. It prints
  `PASS name n=.. seed=..` or `FAIL name seed=.. counterexample=<shrunk program>`,
  and writes the failing program to `checks/props/failures/` so it can
  become a corpus program.
- Tiers: by default about 25 cases for the compile-and-run properties
  (whole-program compiles take 2–10 s each) and 200 for laws. `SLOW=1`
  runs 10× that. Seeds are fixed per row, so a row is repeatable; `--seed`
  explores.
- Rows: `P13.0` laws (C3, reader, hierarchy); `P13.1` `matches-oracle` on
  gc; `P13.2` on llvm; `P13.3` determinism and non-interference on gc;
  `P13.4` expectations on llvm (size, heap, stack). `checks/affected.sh`
  maps `src/` and `rt/` to them.

## 5. P8.0

P13.3 covers what P8.0 guarded: that the GC lane is unaffected by other
lowerings, and that its output is deterministic. PR #25 proposes retiring
P8.0 (its author's check) in favor of P13.3. The comment is drafted for review
first. Until its author agrees, P8.0 stays in the tree, pinned where it is.

## Testing the harness itself

- Each property has a planted-fault check, run once when the property is
  added and recorded in its DECISIONS entry. For example, a lowering
  adapter that drops the last `prn` must fail `matches-oracle` and shrink
  to a one-form program. A `size-bound` with k set below 1 must fail.
- The determinism property is falsified with a build that leaks a
  gensym, the D192 shape.
