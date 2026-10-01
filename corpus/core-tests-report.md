# P2.3 / P2.GATE measurement: let-go core tests through the backend

Measured 2026-10-01 on a frozen snapshot of the tree (git HEAD 1a65573 plus other agents'
uncommitted `src/` edits; md5 of `src rt checks` excluding `.rtlib` = `75daf80d25389c948ae06cae84d71697`).
The live tree moved during the run (a first pass on it differed on 2 files: `transducer_test`, `string_split_test`),
so these numbers are for that snapshot only. let-go test files at 4e769212 (`corpus/core-tests.txt`).
Per-file rows: `corpus/core-tests-results.tsv`. Nothing under `src/` or `rt/` was changed.

## Totals

| measure | value |
|---|---|
| files MATCH / run (oracle = `run-tests.sh` summary + FAIL/ERROR lines equal) | **20 / 44** as `run-tests.sh` runs them; 21 / 44 counting `chunked_seq_test` via an ns-named scratch copy |
| deftests passing under the backend (no FAIL/ERROR line) | **133 / 273 = 48.7%** as run; **144 / 273 = 52.7%** with the chunked_seq workaround |
| P2.GATE bar (>= 90%) | 246 / 273. **Not met**: short by 113 as run (102 with the workaround counted) |
| assertions | native 870 evaluated; backend 680 evaluated in the 39 files that printed a summary, 522 of them passed (no native failures anywhere) |
| timeouts | 0 (wall per file 11-21 s at machine load ~20, includes `sem.sh` queue wait; 7-14 s at load 3) |

`chunked_seq_test.lg` declares `test.chunked-seq`, so native `require` looks for `test/chunked_seq.lg` and the
native side prints no summary. Run from a copy at that name it passes 11/11. This is a harness gap, not a backend one.

## Failure taxonomy

By file (23 non-passing files with the chunked_seq workaround, 24 as run; string_replace_fn appears in two rows, so file counts sum to 24 with it counted twice):

| class | files | deftests lost | detail |
|---|---|---|---|
| missing native / stdlib twin (`TypeError: nil is not a function`, an unlinked extern; the message carries no var name, names below come from the `$ext_*` globals in the emitted WAT) | 14 | 70 | zip 20, data/diff 15, `.getBytes` 8, walk 6, set_ns 5, persistent_set 4 (disj, meta, set/difference, set/intersection), transient 3, math 2, update-keys/vals 2 (`core/meta`), lazy-seq? 1, map-entry? 1, with-out-str* 1, sorted-map/set 1, replace-literal-fn 1 (`str-replace-first`) |
| Phase-2 constant (compiles, throws when evaluated) | 3 (string_replace_fn shared) | 10 | `let-go.lang.Regex`: string_split 3, string_replace_fn 5; `(var x)`: def_meta 2 |
| whole-program abort at run time | 1 | 7 | thrown_test: `error: lower-wasm: Phase-2 constant var` in `_main`, no summary |
| harness / driver (`--test` mode, `run-tests.sh`) | 5 | 41 | quality.* not on backend `-source-paths` (35 deftests, `compile: unable to load namespace`); macro-state cascade (try_finally 6, `compile: unresolved symbol <deftest>`); no-ns files (top_level_do, harness_load_only: 0 deftests); plus chunked_seq (passes only with an ns-named copy) |
| wrong value (no trap) | 1 | 1 | file_var: `*file*` reads nil (`string?` false) |

(129 deftests lost = 70 + 10 + 7 + 41 + 1; clojure_math also hits `+ on a non-Int operand (numeric tower is Phase 2)` once, behind the missing twins.)

By error event (158 FAIL/ERROR lines in the backend runs): 129 `nil is not a function`, 20 `Phase-2 constant Regex`,
6 `Phase-2 constant var`, 1 `*file*`-related assertion false, 1 `ends-with? expected non-nil string` (cascade from nil `*file*`),
1 numeric-tower trap. There are no `thrown?`/`are`/`with-redefs`/`binding` harness gaps in this corpus:
`select-core-tests.sh` excludes `with-redefs`/`binding`, no file uses `are`, and `thrown?` appears only in thrown_test, which
aborts earlier on `(var x)`.

## Top 10 blockers, ranked by deftests unblocked

"Alone" = deftests that would pass once only this is fixed (assumes nothing else hides behind it; the rest are upper bounds).
Owner: backend = `src/`, rt = `rt/`, harness = `checks/run-tests.sh` / `src/testshim.lg` / driver `--test`.
Repros are plain lg, run with `WASM_RUN=checks/wasm-run.sh checks/oracle.sh r.lg`; each printed `MISMATCH` in this run (native result shown).

| # | blocker | deftests | owner | fix, one line | repro (native output) |
|---|---|---|---|---|---|
| 1 | `quality.cost`/`quality.terms` not loadable: backend side uses `-source-paths src:<test dir>`, native needs `let-go/scripts`; catalog also reads `../scripts/quality` by cwd | 35 (quality_cost 24, quality_terms 11); downstream pass rate unverified | harness | add the scripts dir to the backend `-source-paths` and run from `let-go/test` | `(ns q (:require [quality.terms :as t]))` `(deftest a (is (= 20.0 (t/mass {:cc 5 :sloc 16}))))` via `run-tests.sh q.lg`: `compile: ... unable to load namespace quality.terms` |
| 2 | `clojure.zip` twin missing (22 externs: node down up left right edit insert-* remove next end? ...) | 20 | rt | port zip.lg's defns into rt | `(ns r (:require [clojure.zip :as z]))` `(println (z/node (z/down (z/vector-zip [1 2]))))` -> `1`; wasm `nil is not a function` |
| 3 | `clojure.data/diff` missing | 15 | rt | port data.lg | `(ns r (:require [clojure.data :as d]))` `(println (d/diff {:a 1} {:a 2}))` -> `[{:a 1} {:a 2} nil]` |
| 4 | `(var x)` special form is a Phase-2 constant; thrown_test also needs `set-test`, `test/run-test-var`, `test/test-var`, `quiet-helper` (test-ns reflection) | 9 (def_meta 2, thrown 7); def_meta also needs `meta`/`find-ns`/`ns-name`; thrown likely unreachable | backend (+harness) | lower `(var sym)` to the var-table cell | `(def x 1)` `(println (:name (meta (var x))))` -> `x`; wasm `Phase-2 constant var` |
| 5 | regex literal with an escape (`#"\n"`) is Phase-2 constant `let-go.lang.Regex` (`#","` and `#":"` lower fine); also reached inside `split-lines` and `replace` with fn | 8 (string_split 3, string_replace_fn 5; replace-literal-fn also needs `str-replace-first`) | backend | lower regex constants beyond single-literal patterns | `(ns r (:require [clojure.string :as str]))` `(println (str/split "a\nb" #"\n"))` -> `[a b]` |
| 6 | `(.getBytes s)` / `(.getBytes s "UTF-8")`: `core/.` interop unlinked, no String.getBytes twin | 8 (2 of 10 already pass) | backend + rt | lower `(. s getBytes ..)` to an rt twin returning the int-array | `(println (alength (.getBytes "abc")))` -> `3` |
| 7 | `clojure.set` twin missing (`union difference intersection subset? superset? map-invert rename-keys`) | 7 (set_ns 5, persistent_set 2) | rt | port set.lg | `(ns r (:require [clojure.set :as set]))` `(println (set/union #{1} #{2}))` -> `#{2 1}` |
| 8 | `clojure.walk` twin missing (prewalk postwalk keywordize-keys ...) | 6 (4 alone; walk-on-maps also needs `sorted-map`, map-entry?-predicate needs `map-entry?`) | rt | port walk.lg | `(ns r (:require [clojure.walk :as w]))` `(println (w/postwalk #(if (number? %) (inc %) %) [1 [2]]))` -> `[2 [3]]` |
| 9 | a user `defmacro` whose body touches a program-level `def` (atom) fails at native compile time; the rest of the file is dropped and `_main` still calls every deftest, so the whole file is lost | 6 (try_finally, all) | backend driver (+shim: epilogue should skip undefined deftests) | evaluate program `def`s natively before expanding macros, or stub the failing form | `(def n (atom 0))` `(defmacro cnt [] (swap! n inc) nil)` `(defn a [] (cnt) 1)` `(println (a))` -> `1`; wasm `Executing macro #'user/cnt ... swap expected Atom`. In a test file: `run-tests.sh` prints `compile: error: ir/build: unresolved symbol b` |
| 10 | `core/meta` unlinked although `rt/wasm/core.lg:888` defines `meta` (no `:twin` marker, not in `extra-twins`) | 3 alone (update_keys_vals 2, set-with-meta); feeds def_meta and gold return_hint_metadata | rt | add the `:twin` marker or an `extra-twins` row | `(println (meta (with-meta [1] {:a 1})))` -> `{:a 1}` |

Tail (12 deftests): `disj`, `disj!`, `dissoc!` 3 (`(println (disj #{1 2} 1) (persistent! (disj! (transient #{1 2}) 1)) (persistent! (dissoc! (transient {:a 1 :b 2}) :a)))` -> `#{2} #{2} {:b 2}`);
`map-entry?` 2 (`(println (map-entry? (first {:a 1})))` -> `true`); `clojure.math` twin 2 (`m/round m/sqrt m/PI ...`; `(ns r (:require [clojure.math :as m]))` `(println (m/round 2.7) (m/sqrt 16) m/PI)` -> `3 4.0 3.141592653589793`);
`sorted-map`/`sorted-set` 1 (`(println (sorted-map :b 1 :a 2))` -> `{:a 2, :b 1}`); `with-out-str` 1 (`(println (with-out-str (pr {:b 1})))` -> `{:b 1}`);
`lazy-seq?` 1; `to-array` 1 (`(println (alength (to-array [1 2 3])))` -> `3`); `*file*` 1 (`(def f *file*)` `(println (string? f))` -> `true`, wasm prints `false`, a wrong value rather than a trap).
Harness-only, 0 deftests: files without an `ns` form (top_level_do_test, harness_load_only_test: `(assert (= 2 (+ 1 1)))` alone gives `native run printed no summary: ... unable to load namespace`);
ns/file-name mismatch (chunked_seq_test, 11 deftests pass once the native side can load it).

Reading the ranking against the gate: pure rt twins (zip, data, set, walk, meta, the tail) account for about 62 deftests, so rt work alone reaches roughly 195/273 (71%).
The bar stays 246 of 273, so it needs item 1 (35) as well; thrown_test (7, test-ns reflection, `run-tests.skip`-class) is the one file that may be unreachable, which caps the gate at 266.

## test/gold pairs (`checks/wasm-run.sh <x.cljc>`, stdout diffed against `<x>.out`)

| pair | stdout vs `.out` | wasm exit | first differing line / error |
|---|---|---|---|
| dynvar_callbacks | MISMATCH | 1 | missing `[[100 100] [:keep] 200 [100] true (1 2 3) 100 [100] 100]`; `binding of user/*x* is not supported (only *out*)` |
| dynvar_threads | MISMATCH | 1 | missing `[:a :b :inner [:p :q] :captured :m [:fm :base] [:ma :mb :base] [:pm :pm] :root]`; `unsupported top-level form defprotocol` |
| macro_literal_kind_field | MISMATCH | 1 | missing `[[:map :map :set :other :map] [:map :map :set :other :map]]`; `unsupported top-level form defprotocol` |
| map_macroexpansion_eval | MATCH (stdout) | 1 | trailing `(shutdown-agents)`: `nil is not a function` (`core/shutdown-agents` unlinked); `oracle.sh` would say MISMATCH exit |
| ns_threads | MISMATCH | 1 | missing `[gold.a [gold.a gold.b user] gold.b [gold.b user]]`; `binding of core/*ns* is not supported (only *out*)` |
| return_hint_metadata | MISMATCH | 1 | missing `[7 [{:tag long} {:tag long}]]`; `nil is not a function` (extern `core/meta`) |
| set_macroexpansion_eval | MATCH (stdout) | 1 | same `(shutdown-agents)` trailing failure; `oracle.sh` would say MISMATCH exit |

Native lg matches every `.out` (exit 0). Strict stdout+exit: 0 / 7; stdout only: 2 / 7.

## Commands

```
S=/private/tmp/claude-501/-Users-matt-projects-new-3p-joint-xsofy/fca6f592-886f-4b90-9538-46a9d7127210/scratchpad/p23
cp -R dev/lower-wasm $S/snap          # frozen tree; md5 above
# per file, from let-go/test (cwd matters for quality_cost's ../scripts), 3 in parallel:
cd ~/projects-new/3p/let-go/test
KEEP=1 checks/sem.sh timeout -k 5 300 env KEEP=1 \
  SRC_PATHS=$S/snap/rt:~/projects-new/3p/let-go:~/projects-new/3p/let-go/test:~/projects-new/3p/let-go/scripts \
  $S/snap/checks/run-tests.sh ~/projects-new/3p/let-go/test/<file>.lg
# (chunked_seq_test.lg: same command on a copy named test/chunked_seq.lg)
# gold:
checks/sem.sh checks/wasm-run.sh ~/projects-new/3p/let-go/test/gold/<x>.cljc | cmp - <x>.out
```
`run-tests.sh` as shipped sets native `-source-paths` to `rt:<test dir>` only, which cannot resolve `test.<ns>` names
(`unable to load namespace test.conditionals-test`); the `SRC_PATHS` env override above is required for this corpus
(let-go root so `test/<name>.lg` resolves). Per-ERROR messages came from a second snapshot whose `driver.lg` test macros and
`testshim.lg` print `ex-message` (snapshot only; scratch `snap2`). The error text names no var, so the var names are the
`(global $ext_*)` entries of each emitted `.wat`.

## Not in DECISIONS.md, proposed

- `run-tests.sh` should default native `-source-paths` to `rt:<let-go root>:<test dir>` for files under let-go/test (or the corpus list should carry the root).
- `--test` mode should skip `_main` calls to deftests that failed to define, so one bad form costs one test, not the file.
- Count a deftest as passing only when the backend run prints no FAIL/ERROR line for it (used here); the shim prints no per-test pass line, so a test aborted by a whole-program trap counts 0.
