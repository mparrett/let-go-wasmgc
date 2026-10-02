# review5: adversarial review of the in-module evaluator (P7.R, round 3, 2026-10-02)

This is a read-only review of P7.0 (`rt/wasm/eval.lg`, D160) and the backend half of P7
(`src/driver.lg` program table, D161), plus the registry twins in `rt/wasm/natives.lg` that
evaluated code reaches. Nothing outside `corpus/review5/` was edited. All runs used a frozen copy
of `src/ rt/ checks/ host/`, taken at 10:49 from joint 871be67 with the uncommitted Phase 7 diff
(md5: eval.lg 2c9017b8, natives.lg 13ad8cfd, driver.lg 5af27eb3, lower_wasm.lg 7366b067). The copy
is at `<scratch>/ws/dev/lower-wasm`, with `corpus/` and `tools/` symlinked back. Verdicts come from
`checks/oracle.sh`. Native lg is `lg-4e76921230`.

Layout:
- `probes/<group>/*.lg`: 72 oracle programs. Line 1 states native's behaviour. Most go through
  `show`, which prints `form => value` or `ERR "<ex-message>"` and uses a bare `catch` so that class
  dispatch (a named limit) stays out of the way. Fn addresses in messages are normalised to `<FN>`.
- `probes/program/*.lg`: run with `LG_ARGS="-source-paths <abs>/corpus/review5/lib"`. `lib/r5lib/`
  holds the library namespaces.
- `bugs/bug-NN-*.lg`: minimal repros. Native's output is in line 1. All 28 MISMATCH.
- `results/`: `<group>-<name>.verdict` plus both sides' out/err, and the `summary-run*.txt` files.
  Some early `*.native.out` files were clobbered by the driver's own lg call. `ndiff.sh
  <group>-<name>` reruns native and diffs it against the kept wasm output.
- `run.sh <progs>`: oracle verdicts with outputs kept. `LW_TREE=<live dev/lower-wasm>` reruns on HEAD.

## Bugs, ranked (silent wrong answer > uncatchable trap > wrong error text > missing feature)

Severity tiers: **S1** silent wrong answer, or wrong control flow; **S2** uncatchable trap or hang;
**S3** wrong error text; **S4** missing feature that is not a recorded limit. Owner is a guess.

| # | sev | repro | native | module | owner |
|---|---|---|---|---|---|
| 14 | S1+S2 | `bugs/bug-14-for-is-eager.lg`, `bug-14b-...side-effects.lg`, `probes/deep/x08-for-large.lg` | `(take 3 (for [x (range)] (* x x)))` → `(0 1 4)`; `(first (for ...))` realises one element: `[:first-only [0]]`; a 20000-element `for` is instant | uncatchable `error: Maximum call stack size exceeded` (it escaped show's try in run1 of m02); `[:first-only [0 1 2 3 4]]`; x08 still running at the 300 s cap | eval.lg `for-emit`: `concat-list` is `cat-list` = `(apply list (concat a b))`, which is eager, recursive and O(n²). Native's `for` is lazy per element |
| 01 | S1 | `bugs/bug-01-eval-catch-misses-thrown-nonexceptions.lg` | `(eval '(try (throw "s") (catch e [:caught e])))` → `[:caught s]`; also catches `(throw 42)` and case's `No matching clause: ` string | the handler never runs; `"s"` escapes the evaluated try (`error: "s"` uncaught; inside an outer bare catch it shows as `ERR "s"`, see t02 lines 5-7) | eval.lg `run-try`: `(catch Exception e ...)` compiled in the module does not catch a thrown non-exception value. Use a bare catch |
| 02 | S1 | `bugs/bug-02-declare-makes-var-bound.lg` | `(declare x)` / `(def x)` leave the var unbound: `bound?` false, and a later `(defonce x 5)` defines it → `false false` / `5` | `true true` / `nil`: defonce silently does nothing | eval.lg `sf-def` 1-arg branch writes `:val nil`; `bound?*` tests `(contains? cell :val)` |
| 19 | S1 | `bugs/bug-19-def-after-in-ns-in-one-do.lg` | `(do (in-ns 'r5.ct) (def ctv 1))` → `#'r5.ct/ctv` | `#'user/ctv`: the var lands in the old namespace | eval.lg `sf-def` interns with the compile-time `cur-ns`. Native resolves the def's ns when it runs |
| 04 | S1 | `bugs/bug-04-core-var-equality.lg`, `probes/special/s12-var-identity.lg` | `(= #'inc #'inc)`, `(= (var inc) (var clojure.core/inc))`, `(get {#'inc :found} #'inc)`, `(count (set [#'inc #'inc #'dec]))` → `true true :found 2` | `false false nil 3`; also `(= #'inc (eval '(var inc)))` false. Vars of evaluated defs and program vars compare fine | eval.lg `core-var` builds a fresh stand-in with a fresh `:lw/var` closure each time. Cache one per name |
| 20 | S1 | `bugs/bug-20-ns-publics-lists-private.lg` | `ns-publics` leaves out a `defn-` made by evaluated code → `false true` | `true true` | natives.lg `publics-of` does not filter `:private` meta |
| 15 | S1 | `bugs/bug-15-ns-resolve-qualified-sym.lg` | `(ns-resolve 'user 'r5.f/k)` → `nil` | `#'r5.f/k` | natives.lg `ns-resolve`: `(if (namespace sym) (canon (namespace sym)) nm)` redirects to the symbol's namespace |
| 23 | S1 | `bugs/bug-23-find-var-program-var.lg` (needs LG_ARGS) | `(find-var 'r5lib.a/pub)` → `#'r5lib.a/pub`, the same as `resolve` | `nil` (`resolve` works; the main ns's own vars work too) | natives.lg `find-var` gates on `ns-exists?`, and library program namespaces are not in `:nss` |
| 25 | S1 | `bugs/bug-25-evaluated-macro-form-is-nil.lg` | an evaluated `defmacro` sees the call in `&form` → `"(r5-form 1 2)"` | `"nil"` (D161 records nil `&form` for PROGRAM macros only; evaluated macros are not covered) | eval.lg `m-defmacro` binds `&form` to nil; `expand` could pass the form |
| 16 | S1 | `bugs/bug-16-private-evaluated-var-visible.lg` | a `defn-`/`^:private` def made by evaluated code is not reachable qualified from another ns: `Can't resolve r5.a/priv in this context` | `:p` / `2` (it succeeds) | eval.lg `resolve-global` / `lookup-in` never checks `:private` on cells. D161's "privates are listed" covers the program table only |
| 12 | S1 (low) | `bugs/bug-12-duplicate-arity-picks-first.lg` | `((fn ([a] 1) ([b] 2)) 0)` → `2` (the last same-count arity wins) | `1` | eval.lg `pick-arity` takes the first match. The input is ill-formed, so the blast radius is small |
| 03 | S3 | `bugs/bug-03-catch-body-compile-error-chain.lg`, t03 lines 7-11, s03 line 11 | a compile error inside a catch body has two extra layers from native's catch desugar: `compiling if then branch` / `compiling let body` / ... | the chain lacks both layers | eval.lg `sf-try`: wrap the handler body's compile in those two contexts |
| 06 | S3 | `bugs/bug-06-uncaught-eval-compile-error-report.lg`, `probes/traps/k08` | uncaught: first error line `error: calling eval` | `error: CompileError: compiling let body` | top-level report of an error out of `core/eval` (host or lower_wasm.lg printer). Native adds a `calling eval` layer only in the uncaught report; `ex-message` already matches |
| 11 | S3 | `bugs/bug-11-macro-error-missing-calling-layers.lg`, m02 line 8, s08 lines 14/16 | `Executing macro #'core/let (<fn>) failed\n\tcaused by ExecutionError: calling destructure*\n\tcaused by ExecutionError: calling empty?\n\tcaused by ExecutionError: calling seq\n\tcaused by seq expected Seqable`; when-let has `calling throw` | only `caused by seq expected Seqable` | eval.lg expanders run as plain fns, so native's per-call `ExecutionError: calling X` frames are missing. Possibly fold into D160's "Executing macro" limit |
| 07 | S3 | `bugs/bug-07-def-nonsymbol-error-text.lg` | `def: first argument must be a symbol, got ("s")` | `got (s)` | eval.lg `sf-def`: use `pr-str` |
| 13 | S3 | `bugs/bug-13-overflow-error-prefix.lg`, v01 lines 1-3 | `ExecutionError: integer overflow` | `integer overflow` | eval.lg call path / runtime add/mul. Native's direct call carries the prefix (via `reduce` it does not) |
| 10 | S3 | `bugs/bug-10-throw-arity-text.lg` | `(throw)` → `wrong number of arguments 0` | `ExecutionError: function <fn throw-value 0x0> expected 1 args, got 0` | eval.lg core table: `throw` is an lg fn value. Same family as 18 |
| 18 | S3 | `bugs/bug-18-in-ns-arity-text.lg` | `(in-ns)` → `wrong number of arguments 0` | `ExecutionError: function <fn in-ns* 0x0> expected 1 args, got 0` | eval.lg `in-ns*` (fixed arity). natives.lg's `in-ns*` already raises native's text |
| 17 | S3 | `bugs/bug-17-require-string-error-text.lg` | `require expected Symbol or Vector, got let-go.lang.String` | `... got "r5.g"` | eval.lg `require*` uses `pr-str spec`; natives.lg `tname` gives the type name |
| 27 | S3 | `bugs/bug-27-with-out-str-context-text.lg`, e02 line 14 | `compiling arguments (core/fn [] (nope))` | `compiling arguments (fn [] (nope))` | eval.lg `with-out-str` expander: emit `core/fn` |
| 08 | S3 | `bugs/bug-08-call-float-type-name.lg` | `TypeError: let-go.lang.Float is not a function ` | `TypeError: lower-wasm: unknown value type is not a function ` | runtime type-name of Float in the call-non-fn path (lower_wasm.lg / core) |
| 09 | S3 | `bugs/bug-09-long-nil-error-text.lg` | `nil can't be coerced to long` (evaluated and compiled) | ` can't be coerced to long` in both (`str` of nil, not `pr-str`) | runtime `long` twin (not eval-specific; `double` is right) |
| — | S3 | `probes/eval/e07` lines 6-10, 18 | `(eval *ns*)` → `CompileError: cannot compile a value of type let-go.lang.Namespace as a form: <ns user>`; an Atom inside a form is refused the same way | `Can't resolve <ns user> in this context` (the ns stand-in is a Symbol); for the atom, `count expected Counted` (taken as a constant) | eval.lg `comp*`: refuse ns stand-ins and atoms with native's text. No separate repro |
| 05 | S4 | `bugs/bug-05-refer-from-builtin-ns.lg`, `probes/ns/n04` | `(require '[clojure.string :refer [join]])` and `(ns x (:require [clojure.string :refer [blank?]]))` make `join`/`blank?` resolve unqualified | `Can't resolve join in this context` | eval.lg `resolve-global`: a refer to a builtin ns should fall back to the core table's `"string/join"` entry |
| 26 | S4 | `bugs/bug-26-out-err-unresolvable.lg`, e02 line 10, e06 | `*out*` / `*err*` resolve in evaluated code | `Can't resolve *out* in this context`, so `(binding [*out* ...])` fails with that instead of D160's named text | eval.lg core table lacks `*out*`/`*err*` |
| 24 | S4 | `bugs/bug-24-collection-meta-symbol-evaluated.lg`, `probes/special/s13-type-hints` | `^{:tag String} [1]` and `(count ^String [1 2])` work; metadata symbols are not resolved | `Can't resolve String` via `compiling collection metadata` | eval.lg `with-meta-of` compiles the meta map. Native keeps it as data (also def meta: `(:k (meta (def ^{:k (inc 1)} x 1)))` is `(inc 1)` natively, and the module MATCHes there) |
| 21 | S4 | `bugs/bug-21-swap-five-extra-args.lg`, i01 line 5, i02 line 7 | `(swap! a f 1 2 3 4 5)` works | `function <mfn swap! 0x0> doesn't have a 7-arity variant`, from COMPILED code; 6 extra args in evaluated code fail too. D160/D161 record 7+ extra args, but 5 already fails | runtime `swap!` twin arities (rt/), not the evaluator |
| 22 | S4 | `bugs/bug-22-defs-before-ns-form.lg` | defns in `user` before the main file's `(ns ...)` compile and run: `:ok 1` | the whole program is refused: driver `ir/build: unresolved symbol helper` | driver.lg (forms before the ns form are built in the wrong ns). Not eval-specific; found because mk.sh put helpers above `ns` |
| — | S4 | `probes/program/p06-toplevel-in-ns.lg` | a top-level `(eval '(in-ns 'r5.moved))` makes the NEXT program form `(def y 1)` define `r5.moved/y` | `Can't resolve r5.moved/y`: program forms compile statically into the main ns | driver.lg. Probably inherent to static compilation; record it as a limit rather than fix it |

## Probes that MATCHed (30 of 72)

- deep 7/8: 500/5000/20000-deep non-tail evaluated recursion all MATCH (the stack limit holds at
  20000), as do 2000-deep inside try, a 1000-deep nested form, 3000-element literals, a 200000-step
  loop and 1000-deep mutual letfn. x08 fails on bug 14.
- special 6/13: eval order (fn position first, map/set/vector elements, case arg), shadowing (locals
  over core fns and macros but not specials, user-defined `when`), closures over loop/doseq/catch
  bindings, destructuring (24 cases), truthiness, misc forms. Mismatches: s03 (bug 03), s05
  (bug 12), s08 (bug 11), s09 (bug 07), s10/s12 (bug 04), s13 (bug 24 + interop limit).
- macros 3/6: threading/cond/case/condp (incl. odd cond, case on lists/vectors/nil/strings, the
  `No matching clause` throw), misc macros (assert/pre/post, with-redefs of an evaluated var, while,
  doseq :while), threading edges. Mismatches: m02 (bug 11; bug 14 before the edit), m04
  (macroexpand-1 only, named), m06 (bug 25).
- eval 3/7: eval-in-eval and non-forms, compiled↔evaluated error crossing, lazy seqs/delays.
  Mismatches: e02 (bugs 26, 27), e03 (native quirk only, see below), e06 (bug 26), e07 (S3 row
  above + named var-get limit).
- interop 1/3: transducers MATCH; i01/i02 differ only on bug 21 / the named swap! limit (all their
  other lines match after the edit).
- traps 5/9: every wrong-type call in k01 (18 forms) and k02 (17) raises native's text, catchably.
  k03 is bug 09, k04 bug 08, k05 the named regex limit, k08 bug 06. No uncatchable trap in the
  sweep.
- try 1/3: finally ordering, rethrow, nested finallys and catch shadowing all MATCH (t01). t02 is
  bug 01 + bug 10; t03 is the named class-dispatch limit + bug 03.
- values 2/4: strings/symbols (long names, dots, slashes), collection literals (array-map → hash
  order past 8 entries, computed duplicate keys). v01 is bug 13 + core-table limit (`bit-and`,
  `Math/abs`); v04 is the named D15 limit.
- reader 1/4: `#'x`, meta on literals, `::kw` after in-ns and `::alias/k`. r01/r02/r04 differ only
  on named reader limits (plus r01 line 1, a harness artifact: it prints a fn address).
- ns 0/4: n01 (bug 16 + bug 18), n02 (bug 15), n03 (bug 17 + `alias` absent from the core table,
  named), n04 (bug 05).
- defs 0/5: d01/d02 (bugs 02, 20), d03 (bug 19), d04 (`bound-fn` macro absent, named), d05 (bug 24).
- program 1/6: p04 (main without an ns form) MATCHes. p01 (private macro helper: named; find-var:
  bug 23), p02/p03/p05 (named limits only), p06 (S4 row above).

## Named limits confirmed (not bugs)

- Catch does not dispatch on class (D160): `(try (throw (ex-info "x" {})) (catch String e :str)
  (catch Exception e :exc))` → `:str` (native `:exc`); `(catch Exception e ...)` catches thrown
  strings and AssertionError, which native lets through (t03 lines 1-6).
- Binding/alter/var-get of a program var (D160/natives.lg): `lower-wasm: push-binding! of
  #'r5lib.a/*dyn*: a program var's value is not reachable from its stand-in (named limit)`, and the
  same text for `alter-var-root` and `var-get` (p02, e07).
- Evaluation never writes a program var: after an evaluated `(defn mine [] :redef)`, compiled
  `(calls-mine)` is still `:orig`, and library `reads-plain` is still 7 (p03).
- Program-table privates are listed (D161): `(a/helper 2)` → 200, `a/secret` → 42, and the macro
  `with-helper` expanding to the private helper works (native: Can't resolve) (p01, p02).
- Table stand-ins carry only `:name`/`:ns` (D161): `(:arglists (meta (resolve 'a/pub)))` → nil.
- An eval reached only through a macro expansion gets no table (D161): `CompileError: compiling
  function position\n\tcaused by CompileError: Can't resolve pf in this context` (p05).
- `swap!` with 7+ extra args (D160/D161): `function <mfn swap! 0x0> doesn't have a 9-arity variant`.
  See bug 21: the real threshold is lower.
- Core table subset (D160): `macroexpand-1`, `bit-and`, `alias`, `bound-fn`, `Math/abs`/`.length`
  (interop) → `Can't resolve X in this context`. Compiled `add-watch` gives D139's `lower-wasm:
  core/add-watch has no twin`.
- Reader: `lower-wasm: read-string: BigInt literal 9223372036854775808 (past int64; named limit)`,
  `... Ratio literal 1/2 (no Ratio in the runtime; named limit)`, `... #? reader conditional (named
  limit)`, `... #tag tagged literal (#inst, #uuid, *data-readers*; named limit)`, `lower-wasm: regex
  group flags or name (named limit)`, `lower-wasm: regex missing ) (named limit)`.
- D15 Ratio: `error: wasm trap: lower-wasm: / of two Ints yielding a Ratio (numeric tower, D15)`.
  Note: it is an **uncatchable trap** even inside `(try (eval '(/ 1 3)) (catch e ...))` (v04). This
  breaks the sweep rule; worth raising catchably.
- Arity texts print `<fn>` for native's address (normalised away throughout).

## Native quirks and harness notes

- Native `read-all-string` returns a `VOID` element for each `#_` form (`(count (read-all-string
  "#_(ignored) :kept"))` is 2). The module returns only `:kept` and is the more correct of the two
  (e03's only difference).
- Natively, `(catch Exception e ...)` does not catch thrown strings, numbers or AssertionError,
  which is why `show` uses a bare catch.
- A top-level `(in-ns ...)` in a native program changes the namespace later forms compile in, so ns
  probes wrap their forms in `(defn run [] ...)`.
