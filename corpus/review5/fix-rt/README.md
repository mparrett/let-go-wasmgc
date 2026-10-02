# review5 fix-rt: P7.8 runtime fixes (round 3, 2026-10-02)

Row: `checks/run-corpus.sh corpus/review5/fix-rt` (all MATCH). The library
program sits one level down, where run-corpus does not look, because it needs
the review's lib on the source path:

    LG_ARGS="-source-paths $PWD/corpus/review5/lib" checks/run-corpus.sh corpus/review5/fix-rt/program

| bug | file(s) | fix |
|---|---|---|
| 20 | `bug-20-*`, `bug-20b-*` | `rt/wasm/natives.lg` `interns-of`: ns-publics drops vars whose cell meta (or table stand-in meta) has `:private`; ns-interns keeps them. Both now list program-table vars no cell shadows |
| 15 | `bug-15-*`, `bug-15b-*` | `natives.lg` `ns-resolve` is native's `(resolve (symbol (str ns "/" (name sym))))`: sym's namespace is dropped |
| 23 | `program/bug-23-*` | `natives.lg` `find-var` no longer gates the cell/program-table lookup on `ns-exists?` |
| 21 | `bug-21-*`, `bug-21b-*` | `rt/wasm/core.lg` `swap!`: fixed arities up to D150's 20 params (18 extra args) through `swap-v`/`invoke-vec`. New limit: 19+ extra args raise `function <mfn swap! 0x0> doesn't have a N-arity variant` |
| D15 | `d15-ratio-catchable.lg` | `rt/wasm/math.lg` `div2`: the Ratio and `(/ MinInt64 -1)` limits are `c/raise` (catchable, `lower-wasm: ...` so D142 still keeps them out of `thrown?`), not `wasm/trap` |

## Not fixed here (outside rt/ files this row may edit)

- **09** `(long nil)`: the twin is `src/lw_ext.lg` `long-v` (line 88),
  `(str x " can't be coerced to long")`; `str` of nil is "". Module text
  ` can't be coerced to long`, native `nil can't be coerced to long`. Fix
  (P7.9): `(if (nil? x) "nil" (str x))`, or `wasm.str/value-string` (Go's %v).
- **08** calling a Float: `src/lower_wasm.lg` `$rt_not_fn` (line 2810) names
  only nil/Int/Boolean/String/Atom; module text `TypeError: lower-wasm:
  unknown value type is not a function `. Fix (P7.9): add
  `["(ref.test (ref $Float) (local.get $v))" "let-go.lang.Float"]`, or under
  `*rt*` take the name from `$wasm.core/type-name#1__box`, which knows every kind.
- **13** overflow prefix in evaluated code: eval.lg's core table maps `*` to
  the twin value, whose overflow is unprefixed (correct for `*` as a value).
  Native's direct 2-arg call compiles to the IR op, which carries
  `ExecutionError: `. Fix (P7.7, eval.lg): emit direct binary `+`/`-`/`*` as
  plain-lg `(* x y)` over the operands, which the backend lowers to the op.
- **17** `require` of a string: eval.lg line 1082 `require*` uses
  `(pr-str spec)`. natives.lg's twin already uses the type name. Fix (P7.7):
  `(s/mk-str (c/type-name spec))`, or delegate to `n/require*`.
