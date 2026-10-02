# Backend census: legmacs (2026-10-02)

Each top-level fn unit (one row per arity) lowered alone by lower-wasm and its module validated with wasm-tools; nothing is run. Regenerate with `checks/census.sh legmacs`; per-unit rows in `legmacs.tsv`.

**811/816 units compile** (99.4%): ok 122, unbound-var 684, phase2-const 5. unsupported op: 0; invalid-wat: 0; goto fallback: 0; unsupported tree node: 0.

| bucket | units |
|---|---:|
| `unbound-var` | 684 |
| `ok` | 122 |
| `phase2-const` | 5 |
| `other lower-wasm: binding of clojure.core/*err* is not supported (` | 1 |
| `other lower-wasm: binding of legmacs.modes.letgo/*eval-replace-con` | 1 |
| `other lower-wasm: binding of legmacs.vibe/*vibe-context* is not su` | 1 |
| `other unsupported closure arity > 4 {:fn "u520_eval-last-sexp", :a` | 1 |
| `other unsupported closure arity > 4 {:fn "u521_eval-print-last-sex` | 1 |

`unbound-var` = compiles; reaches at least one var outside the corpus with no wasm definition yet (a run-time `TypeError: nil is not a function `). `phase2-const` = compiles, no unbound var, at least one Phase-2 constant placeholder. Units reaching only the corpus's own vars count as ok: a whole-program compile makes those direct calls.

## Top error heads (5 distinct)

| n | head | example | detail |
|---:|---|---|---|
| 1 | `other lower-wasm: binding of clojure.core/*err* is not supported (` | legmacs/modes/letgo.lg capturing-out (1) | lower-wasm: lower-wasm: binding of clojure.core/*err* is not supported (not a var-table var) {:var #'core/*err*, :fn "u4 |
| 1 | `other unsupported closure arity > N {:fn "<fn>", :a` | legmacs/modes/letgo.lg eval-last-sexp (1) | lower-wasm: unsupported closure arity > 4 {:fn "u520_eval-last-sexp", :arity 5} |
| 1 | `other unsupported closure arity > N {:fn "uN_eval-print-last-sex` | legmacs/modes/letgo.lg eval-print-last-sexp (1) | lower-wasm: unsupported closure arity > 4 {:fn "u521_eval-print-last-sexp", :arity 5} |
| 1 | `other lower-wasm: binding of legmacs.modes.letgo/*eval-replace-con` | legmacs/modes/letgo.lg in-process-eval-backend (1) | lower-wasm: lower-wasm: binding of legmacs.modes.letgo/*eval-replace-context* is not supported (not a var-table var) {:v |
| 1 | `other lower-wasm: binding of legmacs.vibe/*vibe-context* is not su` | legmacs/vibe.lg with-context (1) | lower-wasm: lower-wasm: binding of legmacs.vibe/*vibe-context* is not supported (not a var-table var) {:var #'legmacs.vi |

## Phase-2 constant placeholders: 122 units

Units (any bucket) holding at least one placeholder, by kind (sites in parentheses):

| kind | units | sites |
|---|---:|---:|
| vector | 68 | 89 |
| map | 41 | 50 |
| set | 14 | 18 |
| list | 6 | 7 |
| let-go.lang.Regex | 5 | 5 |
| symbol | 4 | 8 |
| var | 2 | 3 |

## Unbound vars: 146 distinct (top 25 by units)

| var | units |
|---|---:|
| `core/assoc` | 185 |
| `core/nth` | 178 |
| `core/str` | 154 |
| `core/count` | 153 |
| `core/vector` | 132 |
| `core/array-map` | 114 |
| `core/get` | 107 |
| `core/seq` | 94 |
| `core/vec` | 70 |
| `core/subs` | 69 |
| `core/first` | 53 |
| `core/contains?` | 51 |
| `core/conj` | 43 |
| `core/map` | 43 |
| `core/not` | 39 |
| `core/update` | 34 |
| `core/apply` | 33 |
| `core/concat` | 28 |
| `core/some` | 28 |
| `core/max` | 27 |
| `string/blank?` | 27 |
| `string/join` | 24 |
| `core/reduce` | 23 |
| `core/empty?` | 23 |
| `core/nil?` | 22 |

## P1.6 named fns

- legmacs/buffer.lg `row-col-of`: unbound-var
