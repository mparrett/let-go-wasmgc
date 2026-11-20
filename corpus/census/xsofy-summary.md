# Backend census: xsofy (2026-11-19)

Each top-level fn unit (one row per arity) lowered alone by lower-wasm and its module validated with wasm-tools; nothing is run. Regenerate with `checks/census.sh xsofy`; per-unit rows in `xsofy.tsv`.

**1058/1058 units compile** (100.0%): ok 71, unbound-var 971, phase2-const 16. unsupported op: 0; invalid-wat: 0; goto fallback: 0; unsupported tree node: 0.

| bucket | units |
|---|---:|
| `unbound-var` | 971 |
| `ok` | 71 |
| `phase2-const` | 16 |

`unbound-var` = compiles; reaches at least one var outside the corpus with no wasm definition yet (a run-time `TypeError: nil is not a function `). `phase2-const` = compiles, no unbound var, at least one Phase-2 constant placeholder. Units reaching only the corpus's own vars count as ok: a whole-program compile makes those direct calls.

## Top error heads (0 distinct)

| n | head | example | detail |
|---:|---|---|---|

## Phase-2 constant placeholders: 616 units

Units (any bucket) holding at least one placeholder, by kind (sites in parentheses):

| kind | units | sites |
|---|---:|---:|
| var | 333 | 333 |
| vector | 219 | 531 |
| map | 94 | 134 |
| set | 20 | 24 |
| list | 4 | 6 |
| symbol | 1 | 1 |

## Unbound vars: 153 distinct (top 25 by units)

| var | units |
|---|---:|
| `test/test-var` | 333 |
| `core/vector` | 250 |
| `core/nth` | 215 |
| `core/get-in` | 145 |
| `core/array-map` | 127 |
| `core/first` | 120 |
| `core/assoc` | 112 |
| `core/str` | 104 |
| `core/get` | 101 |
| `core/count` | 86 |
| `core/vec` | 78 |
| `core/reduce` | 72 |
| `core/filter` | 65 |
| `core/seq` | 64 |
| `core/nil?` | 60 |
| `core/not=` | 59 |
| `core/max` | 55 |
| `core/contains?` | 54 |
| `core/assoc-in` | 46 |
| `core/conj` | 45 |
| `core/not` | 44 |
| `core/min` | 43 |
| `core/second` | 43 |
| `core/vals` | 36 |
| `core/name` | 35 |

## P1.6 named fns

- xsofy/fov.lg `reveal-line`: unbound-var
