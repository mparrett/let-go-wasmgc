# Backend census: legmacs (2026-11-19)

Each top-level fn unit (one row per arity) lowered alone by lower-wasm and its module validated with wasm-tools; nothing is run. Regenerate with `checks/census.sh legmacs`; per-unit rows in `legmacs.tsv`.

**816/816 units compile** (100.0%): ok 123, unbound-var 687, phase2-const 6. unsupported op: 0; invalid-wat: 0; goto fallback: 0; unsupported tree node: 0.

| bucket | units |
|---|---:|
| `unbound-var` | 687 |
| `ok` | 123 |
| `phase2-const` | 6 |

`unbound-var` = compiles; reaches at least one var outside the corpus with no wasm definition yet (a run-time `TypeError: nil is not a function `). `phase2-const` = compiles, no unbound var, at least one Phase-2 constant placeholder. Units reaching only the corpus's own vars count as ok: a whole-program compile makes those direct calls.

## Top error heads (0 distinct)

| n | head | example | detail |
|---:|---|---|---|

## Phase-2 constant placeholders: 153 units

Units (any bucket) holding at least one placeholder, by kind (sites in parentheses):

| kind | units | sites |
|---|---:|---:|
| vector | 87 | 139 |
| map | 43 | 56 |
| set | 26 | 30 |
| list | 6 | 9 |
| let-go.lang.Regex | 5 | 5 |
| symbol | 4 | 8 |
| var | 2 | 3 |

## Unbound vars: 148 distinct (top 25 by units)

| var | units |
|---|---:|
| `core/assoc` | 187 |
| `core/nth` | 179 |
| `core/str` | 156 |
| `core/count` | 153 |
| `core/array-map` | 113 |
| `core/vector` | 112 |
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
