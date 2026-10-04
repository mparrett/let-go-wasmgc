# Backend census: xsofy (2026-10-03)

Each top-level fn unit (one row per arity) lowered alone by lower-wasm and its module validated with wasm-tools; nothing is run. Regenerate with `checks/census.sh xsofy`; per-unit rows in `xsofy.tsv`.

**1062/1064 units compile** (99.8%): ok 71, unbound-var 976, phase2-const 15. unsupported op: 0; invalid-wat: 0; goto fallback: 0; unsupported tree node: 0.

| bucket | units |
|---|---:|
| `unbound-var` | 976 |
| `ok` | 71 |
| `phase2-const` | 15 |
| `optimize error` | 2 |

`unbound-var` = compiles; reaches at least one var outside the corpus with no wasm definition yet (a run-time `TypeError: nil is not a function `). `phase2-const` = compiles, no unbound var, at least one Phase-2 constant placeholder. Units reaching only the corpus's own vars count as ok: a whole-program compile makes those direct calls.

## Top error heads (1 distinct)

| n | head | example | detail |
|---:|---|---|---|
| 2 | `optimize error` | main.lg read-dismiss-key! (1) | optimize error: validate after licm: block #0 branch to b1 passes 0 args but b1 has 1 params |

## Phase-2 constant placeholders: 509 units

Units (any bucket) holding at least one placeholder, by kind (sites in parentheses):

| kind | units | sites |
|---|---:|---:|
| var | 333 | 333 |
| vector | 97 | 120 |
| map | 90 | 114 |
| set | 20 | 24 |
| list | 4 | 6 |
| symbol | 1 | 1 |

## Unbound vars: 153 distinct (top 25 by units)

| var | units |
|---|---:|
| `test/test-var` | 333 |
| `core/vector` | 321 |
| `core/nth` | 214 |
| `core/get-in` | 146 |
| `core/array-map` | 132 |
| `core/first` | 119 |
| `core/assoc` | 115 |
| `core/str` | 106 |
| `core/get` | 100 |
| `core/count` | 86 |
| `core/vec` | 78 |
| `core/reduce` | 71 |
| `core/filter` | 65 |
| `core/seq` | 64 |
| `core/nil?` | 62 |
| `core/not=` | 59 |
| `core/max` | 55 |
| `core/contains?` | 53 |
| `core/assoc-in` | 47 |
| `core/not` | 45 |
| `core/conj` | 44 |
| `core/min` | 43 |
| `core/second` | 42 |
| `core/vals` | 36 |
| `core/name` | 35 |

## P1.6 named fns

- xsofy/fov.lg `reveal-line`: unbound-var
