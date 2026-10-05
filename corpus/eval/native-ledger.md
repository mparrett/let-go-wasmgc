# The evaluator on its native seam: ledger (eval-seam, 2026-10-04)

`rt/wasm/eval.lg` reaches its host only through the seam fns its header lists and defines none
of them (D187); a host file loaded after it defines them. `rt/wasm/eval_wasm.lg` is the module's
host, `rt/wasm/eval_native.lg` the host over real let-go namespaces and vars under stock lg. `checks/eval-native.sh` (row P7.10) runs every program of `corpus/eval/*/`,
`corpus/eval/program/multi/` and `corpus/review5/fix-eval/` under stock lg twice, with let-go's
`eval` and with `eval` rebound to `wasm.eval/eval` on that seam, and compares them through
`checks/oracle.sh`.

**Result on 2026-10-04 (tree eval-seam-2026-10-04): 35/37 MATCH, 2 known mismatches, wall 6 s.**
Both mismatches have the one cause under "Seam gaps". With a probe that interned the var unbound
(through native `eval` of `(def x)`, not committed), the same run was 37/37.

## MISMATCHes

| program | lines | cause | class |
|---|---|---|---|
| `corpus/eval/macros/destructure.lg` | `(defonce d-once 1)` => nil, then `d-once` => nil (native: `#'user/d-once`, 1) | an evaluated `(def x)` leaves x bound to nil, so defonce's `bound?` is true and it skips the def | seam gap |
| `corpus/review5/fix-eval/bug-02-declare-makes-var-bound.lg` | `true true` (native `false false`), then defonce as above | same | seam gap |

## Seam gaps (what the native seam cannot express in lg today)

- **Unbound intern.** The compiler's def interns with `LookupOrAdd`, which leaves a new var
  unbound; let-go's 2-arg `intern` binds a new var to nil (Clojure's leaves it unbound), and no
  other lg-callable fn interns. let-go's own `ir/build.lg` `build-def` interns through the same
  `intern`. An `intern` that leaves a new var unbound, as Clojure's does, closes this gap.
- **Form source.** The compiler's def adds `:line`/`:column`/`:file` from the reader's
  `FormSource`; lg code has no accessor for it, so an evaluated def's var lacks them on both
  seams (`corpus/review5/bugs/bug-29-evaluated-def-meta-source.lg`).
- **Thread binding test.** `set!` sets the innermost thread binding when there is one, else the
  root. lg cannot ask whether a var is thread-bound, so the native seam compares `@v` with the
  root (`alter-var-root v identity`): when a binding holds the root's identical value, `set!`
  sets the root. No corpus program reaches that case.

## Evaluator bugs (wrong on both seams; repros in `corpus/review5/bugs/`, not fixed here)

- `bug-28-ns-refer-clojure-value.lg`: `(ns x (:refer-clojure :exclude [map]))` is nil natively;
  the evaluator's `ns` expander drops `:refer-clojure` and returns `in-ns`'s value.
- `bug-29-evaluated-def-meta-source.lg`: see "Form source" above.
- Both print the same through the module (`checks/wasm-run.sh`, this branch, 2026-10-04) as on
  the native seam.
- Already on review5's list and seen again here: `(eval *ns*)` (review5 S3 row, e07), and class
  dispatch in `catch` (named limit).

## Native-only differences (the native seam or the runner, not the evaluator)

- **Uncaught CompileError report.** With `eval` rebound to an lg fn, an uncaught evaluator error
  prints `error: CompileError: compiling ...`; native's Go `eval` prints `error: calling eval`
  first. Caught errors (`ex-message`) are the same on both. The module matches native here
  through the backend's wrapping (D166). Seen in review5's `traps/k08` and `bugs/bug-06`; no
  program in the proof corpus leaves an eval error uncaught.
- **A core macro without an expander** (`defmulti`, `deftype`, `future`, `go`, `bound-fn`, ...)
  resolves to a real var natively; the native seam reports it as `Can't resolve`, the text the
  wasm seam gives, instead of calling the macro fn as a fn.
- **Fn addresses** in printed values (`<fn 0x...>`) differ run to run on any host
  (review5 `reader/r01`).

## Named limits: which hold on the native seam

Each probed as `(eval (read-string s))` under native lg vs the native seam (2026-10-04).

| limit (eval.lg header, D160/D165) | native seam |
|---|---|
| tail calls between evaluated fns not trampolined | works natively to the Go stack's depth: 20000-deep non-tail recursion and 50000-step mutual recursion through `letfn` both return |
| catch does not dispatch on the class | holds: it is the evaluator's `try`, so the first clause catches (`(catch String s ..)` catches an ex-info) |
| arity error text `<fn>` / macro frames `<fn name>` | holds (evaluator text) |
| `binding` of a program var or of `*out*`/`*err*`; `set!` of a program var | works natively: real vars, let-go's `push-binding!`/`pop-binding!`, set! inside a binding sets the binding |
| host interop (`.m`, `Foo.`, `new`), deftype, defrecord, defprotocol, reify, defmulti, go, future | holds: no expander, `Can't resolve` (natively each is a real macro or special form) |
| core table holds ~230 names | works natively: every core var resolves (`reductions`, `clojure.string/escape`) |
| macroexpand-1 / macroexpand absent | works natively (let-go's own, expanding with let-go's macros) |
| `(meta v)` of a var taken before a redefinition shows the old meta | works natively (one mutable var) |
| invalid `#"regex"` raises re-pattern's text | works natively (native reader) |
| gensym numbering | holds (different counters) |
| `(eval *ns*)` (review5 e07) | holds: the evaluator returns the namespace, native refuses it as a form |

## Wasm-only constructs and what replaces them natively

| wasm seam | native seam |
|---|---|
| registry `:cur`, `n/set-cur!`/`n/add-ns*`, `n/current-ns` | `*ns*`, `in-ns` |
| cells (`intern-cell!`, `cell-var`, `cell-get`, `:stack`) | real vars: `intern` + `apply-def-meta!`, `deref`, `alter-var-root`, let-go's thread bindings |
| var stand-ins (`#'ns/name` symbols with an `:lw/var` getter), `core-var` | the vars themselves (`find-var`) |
| program table (`install-program-table!`, `prog`, `lookup-in`, `resolve-alias`, `:pmacro`) | not needed: program namespaces, vars and macros are real (`:macro` meta) |
| registry `:aliases`/`:refers`, `canon` | `resolve` in `*ns*`, `ns-aliases`, `find-ns` (`canon` keeps wasm.natives' table as fallback) |
| core table (230 names, `in-ns*`, `require*`, `bound?*`, `set-macro!*`, `throw*`, wasm.natives' var fns) | let-go's core vars; the table only for `concat*` and `wasm.eval/macro-form*` |
| reader code hook (`::k`, syntax-quote, `#"re"`) | let-go's reader |
| `c/raise`, `s/str-bytes`, `c/type-name`, `c/var-value` | `ex-info`/`throw`, `str`, `type`; no program var stand-ins exist |

## Wider run (not part of P7.10)

The same runner over `corpus/review5/probes/*` and `corpus/review5/bugs/`: 88/100 MATCH on
2026-10-04. The 12 others: the unbound-intern gap (d01, d02, d05, bug-02), the uncaught report
(k08, bug-06), `bound-fn` without an expander (d04), `(eval *ns*)` (e07), bug-28 (n04 line 8),
fn addresses (r01), `.length` interop (s13), class dispatch (t03).
