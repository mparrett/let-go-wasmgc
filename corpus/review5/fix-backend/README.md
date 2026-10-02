# review5 backend fixes (P7.9)

`checks/run-corpus.sh corpus/review5/fix-backend`. Fixed here (each file's line 1 is native's behaviour):

- bug-22 `bug-22-defs-before-ns-form.lg`: defns made before the main file's `(ns ..)` form are resolved and
  analysed in the namespace they were defined in (src/driver.lg `tag-ns`/`src-ns`), not the final one.
- bug-06 `bug-06*.lg`: when the program reaches eval, top-level calls of `eval` and of program fns are wrapped
  so an uncaught CompileError reports `error: calling <f>` first, as native's uncaught report does
  (src/driver.lg `calling-wrap`, src/lw_ext.lg `calling-throw`). Caught errors and runtime errors are unchanged
  (06d). Limit: a program fn called through a core HOF from top level (`(doall (map g xs))`) reports without
  the `calling` layer.
- bug-09 `bug-09-long-nil-error-text.lg`: `long` of nil says `nil can't be coerced to long` (src/lw_ext.lg long-v).
- bug-08 `bug-08-call-float-type-name.lg`: calling a Float raises `TypeError: let-go.lang.Float is not a
  function ` ($rt_not_fn in src/lower_wasm.lg names Float).

Not fixed here:

- e07 (`(eval *ns*)`, an Atom inside an evaluated form): belongs to rt/wasm/eval.lg (P7.7). eval receives the
  namespace stand-in, the Symbol `<ns user>`, and resolves it as a symbol; refusing it (and an Atom) with
  native's `cannot compile a value of type let-go.lang.Namespace as a form: <ns user>` is a check in the
  evaluator's compile step. The backend's stand-in is unchanged: giving it a Namespace type name would not
  make eval refuse it.
- p06 (a top-level `(eval '(in-ns 'x))` moves where the NEXT program form compiles): named limit. The module
  is compiled statically, every program form in the namespace the driver saw it in; the in-ns runs only at
  run time, so a later `(def y 1)` still defines the main namespace's `y`.
- D15 Ratio trap (`(/ 1 3)` uncatchable): runtime-side, `rt/wasm/math.lg` raises it with `wasm/trap`; P7.8.
