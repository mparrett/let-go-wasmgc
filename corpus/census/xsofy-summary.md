# Backend census: xsofy (2026-10-01)

Each top-level fn unit (one row per arity) lowered alone by lower-wasm and its module validated with wasm-tools; nothing is run. Regenerate with `checks/census.sh xsofy`; per-unit rows in `xsofy.tsv`.

**1055/1064 units compile** (99.2%): ok 75, unbound-var 969, phase2-const 11. unsupported op: 0; invalid-wat: 0; goto fallback: 0; unsupported tree node: 0.

| bucket | units |
|---|---:|
| `unbound-var` | 969 |
| `ok` | 75 |
| `phase2-const` | 11 |
| `optimize error` | 2 |
| `other unsupported variadic fn (& args) as a closure {:fn "u446_par` | 1 |
| `other unsupported variadic fn {:fn "u110_gen-tuple"}` | 1 |
| `other unsupported variadic fn {:fn "u195_log"}` | 1 |
| `other unsupported variadic fn {:fn "u234_drops"}` | 1 |
| `other unsupported variadic fn {:fn "u235_immune"}` | 1 |
| `other unsupported variadic fn {:fn "u244_runes"}` | 1 |
| `other unsupported variadic fn {:fn "u257_update-entity"}` | 1 |

`unbound-var` = compiles; reaches at least one var outside the corpus with no wasm definition yet (a run-time `TypeError: nil is not a function `). `phase2-const` = compiles, no unbound var, at least one Phase-2 constant placeholder. Units reaching only the corpus's own vars count as ok: a whole-program compile makes those direct calls.

## Top error heads (3 distinct)

| n | head | example | detail |
|---:|---|---|---|
| 6 | `other unsupported variadic fn {:fn "<fn>"}` | xsofy/check.lg gen-tuple (1) | lower-wasm: unsupported variadic fn {:fn "u110_gen-tuple"} |
| 2 | `optimize error` | main.lg read-dismiss-key! (1) | optimize error: validate after licm: block #0 branch to b1 passes 0 args but b1 has 1 params |
| 1 | `other unsupported variadic fn (& args) as a closure {:fn "uN_par` | xsofy/runes.lg parse-runes (1) | lower-wasm: unsupported variadic fn (& args) as a closure {:fn "u446_parse-runes", :name nil} |

## Phase-2 constant placeholders: 484 units

Units (any bucket) holding at least one placeholder, by kind (sites in parentheses):

| kind | units | sites |
|---|---:|---:|
| var | 339 | 347 |
| vector | 95 | 118 |
| float | 30 | 62 |
| set | 20 | 24 |
| map | 20 | 21 |
| list | 4 | 6 |
| symbol | 1 | 1 |

## Unbound vars: 156 distinct (top 25 by units)

| var | units |
|---|---:|
| `test/test-var` | 333 |
| `core/vector` | 319 |
| `core/nth` | 212 |
| `core/get-in` | 146 |
| `core/array-map` | 128 |
| `core/first` | 119 |
| `core/assoc` | 114 |
| `core/str` | 104 |
| `core/get` | 100 |
| `core/count` | 84 |
| `core/vec` | 74 |
| `core/reduce` | 70 |
| `core/filter` | 65 |
| `core/seq` | 64 |
| `core/nil?` | 61 |
| `core/not=` | 59 |
| `core/max` | 55 |
| `core/contains?` | 53 |
| `core/assoc-in` | 47 |
| `core/not` | 45 |
| `core/min` | 43 |
| `core/conj` | 42 |
| `core/second` | 42 |
| `core/vals` | 36 |
| `core/name` | 34 |

## P1.6 named fns

- xsofy/fov.lg `reveal-line`: unbound-var
