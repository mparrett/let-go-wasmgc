# Spec: `eval.lg` as a host-independent let-go interpreter (devbox task)

Written 2026-10-02 evening, during round 3's final gate. Standalone so another
box can pick it up. Status: candidate for round 4 item 4 (ROUND4.md); the
upstream step (design note, PR) waits for the maintainers' conversation, as everything
does. This document is the work order up to and including the local proof.

## Why

`rt/wasm/eval.lg` (new in round 3, D160, D165) is a let-go interpreter
written in let-go: a closure-compiling evaluator over reader data, with the
core macro set as expanders, a ~230-name core table, namespaces and vars in a
registry. It already runs under native lg in the campaign's test tier
(`corpus/intrinsics/eval_test.lg`, 122 deftests, compared against native
`eval`). Nothing in it is wasm-specific; what it IS coupled to is the wasm
runtime's value model and registry.

A let-go program compiled ahead of time (gogen / AOT, the TinyGo lanes) has
no VM linked and therefore no `eval`, the same gap legmacs had in the wasm
module before round 3. An `eval.lg` that depends only on core fns plus a
small "where do namespaces and vars live" seam would give those binaries an
`eval` for the cost of linking one lg file, which gogen would lower like the
rest of core. That is the upstream story, and it is native-only framing.

## Goal

One file, two implementations of a small seam:
- the wasm implementation: exactly today's behaviour (the registry in
  `wasm.natives`, the backend's program table, `wasm.core/var-value`);
- a native implementation over real let-go namespaces and vars, so that
  `(wasm.eval/eval form)` under stock lg agrees with let-go's own `eval` on
  the whole oracle corpus.

Non-goals: new evaluator features; changing the wasm side's behaviour; go
blocks; interop; performance work; any PR.

## The seam as it stands

`rt/wasm/eval.lg` lines 74-160 ("Host layer: the only module-specific
calls" and "The registry, cells and the program table") already isolate most
of it. The touchpoints, from a grep on 2026-10-02 (`n/` = wasm.natives, `c/`
= wasm.core, `s/` = wasm.str):

| touchpoint | used for | native equivalent |
|---|---|---|
| `n/table*`, `n/registry` (9 uses), `n/set-cur!`, `n/add-ns*`, `n/canon*`, `n/ns-exists*?`, `n/current-ns`, `n/the-ns`, `n/find-ns`, `n/all-ns` | current ns, ns creation, aliases, existence | `*ns*`, `create-ns`, `in-ns`, `find-ns`, `all-ns`, `ns-aliases` |
| cells: `intern-cell!`, `cell-var`, `cell-get`, `:stack` (dynamic binding) | evaluated defs | `intern`, real vars, `push-thread-bindings`/`binding` |
| `n/resolve`, `n/ns-resolve`, `n/find-var`, `n/var?`, `n/var-get`, `n/bound?`, `n/intern`, `n/alter-var-root`, `n/alter-meta!`, `n/push-binding!`, `n/pop-binding!`, `n/bound-fn*`, `n/ns-publics` | the var natives the evaluator calls | the same names in core, no stand-ins |
| `c/var-value`, `c/set-var-root!` | reading/writing a program var through its stand-in | `deref`, `alter-var-root` |
| the program table (`install-program-table!`, `prog`, `lookup-in`, `resolve-alias`) | the backend's view of the compiled program's vars/aliases/refers/macros | not needed natively: the program's namespaces ARE the namespaces; macros are real macros (`:macro` meta) |
| `c/raise`, `s/str-bytes`, `s/mk-str`, `c/type-name` | errors with native's text, strings | `ex-info` / `throw`, `str`, `type` |
| `core-table` | which core fns evaluated code may call | natively: `resolve` in `clojure.core`; keep the table only as the wasm implementation |
| `native-tier` atom | the existing switch the test tier flips | becomes the seam selector |

The honest finding of the work is the table above, corrected.

## Deliverables

1. `rt/wasm/eval.lg` with the touchpoints behind a seam: a map or a set of
   defns (`eval-host/*`), chosen once at load (the `native-tier` switch
   generalised). The wasm implementation moves into that seam unchanged.
2. A native implementation of the seam (in `eval.lg` under a flag, or a
   sibling file `rt/wasm/eval_native.lg` the test tier loads; your call,
   stated in the file header).
3. Proof, all native lg, no wasm toolchain needed:
   - `checks/run-intrinsics-native.sh` stays green (122 tests; the count
     guard is automatic);
   - a new runner, `checks/eval-native.sh`: for every program in
     `corpus/eval/{special,macros,fns,errors,ns,reader}/`,
     `corpus/eval/program/` (with `-source-paths corpus/eval/program/multi/lib`
     for `multi/`) and `corpus/review5/fix-eval/`, run it under stock lg
     twice: once as is (native `eval`) and once with `eval` rebound to
     `wasm.eval/eval` on the native seam (a small prelude that
     `alter-var-root`s `#'clojure.core/eval`, or a `-e` wrapper; say which);
     stdout, exit status and error texts must match. Print `n/total MATCH`.
     Target: every program that is not on the named-limits list.
4. A ledger `corpus/eval/native-ledger.md`: each MISMATCH with the cause
   (seam gap / evaluator bug / native-only difference), each named limit
   kept, each wasm-only construct (the program table) and what replaces it.
5. If you find an evaluator BUG (wrong in both implementations), write the
   minimal repro into `corpus/review5/bugs/` with native's output on line 1
   and report it; do not fix the wasm side from the devbox.

## Constraints

- Start from a tree at or after joint commit d953b83 (round 3's gate tree);
  pull before starting; `rt/wasm/eval.lg` stops moving on the main box after
  the gate.
- Edit only `rt/wasm/eval.lg`, the optional `rt/wasm/eval_native.lg`,
  `corpus/intrinsics/eval_test.lg`, `checks/eval-native.sh`,
  `corpus/eval/native-ledger.md`, `corpus/review5/bugs/`. Never `src/`,
  never `rt/wasm/natives.lg` (say what you need from it instead), never the
  wasm side's behaviour.
- Native lg is `$LW_ROOT/lg-bin/lg-e9789b7d53` (let-go e9789b7d).
- No git commit/push/gh from the agent; the runner commits. No upstream
  anything.
- Toolchain on the devbox: lg only, plus the repo. `LW_SLOTS=2` is enough.

## Named limits to expect (not bugs)

From D160/D165 and the eval.lg header: tail calls not trampolined; catch
does not dispatch on class; `binding` of program/core vars; no interop,
deftype, defprotocol, defmulti, go, future (eager), macroexpand; gensym
numbering; macro error frames beyond the three shapes P7.7 fixed; `(eval
*ns*)` (e07). Some of these may simply work natively (catch by class, binding
of real vars): record each as "limit on wasm, works natively" when so; that
list is part of the upstream story.

## After the proof (not part of this task)

A let-go design note (native framing: AOT binaries gain `eval`), the
discussion with the core maintainers, then a PR that places the file where
gogen lowers it. The campaign's standing rule: spin-offs never mention the
wasm backend's internal name; this one can simply say "an evaluator in lg".
