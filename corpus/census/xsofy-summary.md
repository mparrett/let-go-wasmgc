# Backend census: xsofy (2026-10-02)

Each top-level fn unit (one row per arity) lowered alone by lower-wasm and its module validated with wasm-tools; nothing is run. Regenerate with `checks/census.sh xsofy`; per-unit rows in `xsofy.tsv`.

**1056/1064 units compile** (99.2%): ok 71, unbound-var 970, phase2-const 15. unsupported op: 0; invalid-wat: 0; goto fallback: 0; unsupported tree node: 0.

| bucket | units |
|---|---:|
| `unbound-var` | 970 |
| `ok` | 71 |
| `phase2-const` | 15 |
| `other seq expected Seqable` | 6 |
| `optimize error` | 2 |

`unbound-var` = compiles; reaches at least one var outside the corpus with no wasm definition yet (a run-time `TypeError: nil is not a function `). `phase2-const` = compiles, no unbound var, at least one Phase-2 constant placeholder. Units reaching only the corpus's own vars count as ok: a whole-program compile makes those direct calls.

## Top error heads (2 distinct)

| n | head | example | detail |
|---:|---|---|---|
| 6 | `other seq expected Seqable` | xsofy/fire.lg step-fire (1) | seq expected Seqable |
| 2 | `optimize error` | main.lg read-dismiss-key! (1) | optimize error: validate after licm: block #0 branch to b1 passes 0 args but b1 has 1 params |

## Phase-2 constant placeholders: 504 units

Units (any bucket) holding at least one placeholder, by kind (sites in parentheses):

| kind | units | sites |
|---|---:|---:|
| var | 333 | 333 |
| vector | 93 | 114 |
| map | 87 | 109 |
| set | 19 | 22 |
| list | 4 | 6 |
| symbol | 1 | 1 |

## Unbound vars: 153 distinct (top 25 by units)

| var | units |
|---|---:|
| `test/test-var` | 333 |
| `core/vector` | 315 |
| `core/nth` | 211 |
| `core/get-in` | 140 |
| `core/array-map` | 128 |
| `core/first` | 115 |
| `core/assoc` | 112 |
| `core/str` | 104 |
| `core/get` | 97 |
| `core/count` | 85 |
| `core/vec` | 75 |
| `core/reduce` | 69 |
| `core/filter` | 63 |
| `core/seq` | 62 |
| `core/nil?` | 59 |
| `core/not=` | 57 |
| `core/max` | 53 |
| `core/contains?` | 51 |
| `core/assoc-in` | 46 |
| `core/not` | 44 |
| `core/min` | 43 |
| `core/conj` | 41 |
| `core/second` | 38 |
| `core/vals` | 35 |
| `core/name` | 34 |

## P1.6 named fns

- xsofy/fov.lg `reveal-line`: unbound-var
