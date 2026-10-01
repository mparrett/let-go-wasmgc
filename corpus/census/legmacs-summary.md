# Backend census: legmacs (2026-10-01)

Each top-level fn unit (one row per arity) lowered alone by lower-wasm and its module validated with wasm-tools; nothing is run. Regenerate with `checks/census.sh legmacs`; per-unit rows in `legmacs.tsv`.

**814/816 units compile** (99.8%): ok 122, unbound-var 687, phase2-const 5. unsupported op: 0; invalid-wat: 0; goto fallback: 0; unsupported tree node: 0.

| bucket | units |
|---|---:|
| `unbound-var` | 687 |
| `ok` | 122 |
| `phase2-const` | 5 |
| `other unsupported closure arity > 4 {:fn "u520_eval-last-sexp", :a` | 1 |
| `other unsupported closure arity > 4 {:fn "u521_eval-print-last-sex` | 1 |

`unbound-var` = compiles; reaches at least one var outside the corpus with no wasm definition yet (a run-time `TypeError: nil is not a function `). `phase2-const` = compiles, no unbound var, at least one Phase-2 constant placeholder. Units reaching only the corpus's own vars count as ok: a whole-program compile makes those direct calls.

## Top error heads (2 distinct)

| n | head | example | detail |
|---:|---|---|---|
| 1 | `other unsupported closure arity > N {:fn "<fn>", :a` | legmacs/modes/letgo.lg eval-last-sexp (1) | lower-wasm: unsupported closure arity > 4 {:fn "u520_eval-last-sexp", :arity 5} |
| 1 | `other unsupported closure arity > N {:fn "uN_eval-print-last-sex` | legmacs/modes/letgo.lg eval-print-last-sexp (1) | lower-wasm: unsupported closure arity > 4 {:fn "u521_eval-print-last-sexp", :arity 5} |

## Phase-2 constant placeholders: 125 units

Units (any bucket) holding at least one placeholder, by kind (sites in parentheses):

| kind | units | sites |
|---|---:|---:|
| vector | 68 | 89 |
| map | 41 | 50 |
| set | 14 | 18 |
| list | 6 | 7 |
| var | 5 | 9 |
| let-go.lang.Regex | 5 | 5 |
| symbol | 4 | 8 |

## Unbound vars: 150 distinct (top 25 by units)

| var | units |
|---|---:|
| `core/assoc` | 185 |
| `core/nth` | 178 |
| `core/str` | 154 |
| `core/count` | 153 |
| `core/vector` | 132 |
| `core/array-map` | 114 |
| `core/get` | 108 |
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
| `core/reduce` | 24 |
| `string/join` | 24 |
| `core/empty?` | 23 |
| `core/nil?` | 22 |

## P1.6 named fns

- legmacs/buffer.lg `row-col-of`: unbound-var
