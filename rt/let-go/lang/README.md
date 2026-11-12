# rt/let-go/lang — `let-go.lang.*`, shared by every target

let-go's core types live in its VM: Go types in `pkg/vm`, named
`let-go.lang.*` (`let-go.lang.BigInt`, `let-go.lang.Ratio`, ...). The
compiled targets have no Go host, so their versions of that layer are
written in Clojure and live here under the same name, ready to sit beside
`pkg/vm` when this project merges into let-go. `let-go.core` (lg's
user-facing extras) and `core` (clojure.core) are not this layer.

A file here is plain Clojure, not the runtime dialect: no intrinsics, no IR
forms. It is an ordinary library, found on the `rt` source path by its
namespace (`let-go.lang.<name>` in `rt/let-go/lang/<name>.lg`, the
hyphenated path let-go's resolver tries first), so the wasm and llvm
targets, and native lg, run the same source.

## Load order

The rows a target's runtime loads from this directory, in order, before its
own namespaces (`src/lw_rt.lg` reads this table as it reads
`rt/wasm/README.md`'s; the llvm lane reads the same list). A row is plain
lg: its defns compile when a program or the runtime reaches them (D114).

| order | file | ns | requires | owns |
|---|---|---|---|---|
| 1 | `bignum.lg` | `let-go.lang.bignum` | | BigInt and Ratio (below) |
| 2 | `decimal.lg` | `let-go.lang.decimal` | 1 | BigDecimal (below) |

A library deftype becomes a runtime value through `wasm/deftype-struct`
(rt/wasm/intrinsics.lg): the dialect declares a struct for it, and the
backend rewrites the library's `(Name. ..)` and `.-field` forms onto that
struct (git-issue:4d19ae0, D230). Natively the instance stays the deftype's.

| File | Namespace | What it is |
|---|---|---|
| `bignum.lg` | `let-go.lang.bignum` | BigInt and Ratio (deftypes; 32-bit limbs in an int-array, sign apart): parse/print, add sub mul, quot rem mod (let-go's) and ediv emod (big.Int's Euclidean), gcd, compare, nearest-even float64, and `simplify` (let-go's MaybeSimplifyRatio). The wasm runtime loads it (row 1 above) as its BigInt and Ratio values (rt/wasm/numtower.lg, D230); the llvm target does not yet compile it as a library (it refuses a def constant used as a value). |
| `decimal.lg` | `let-go.lang.decimal` | BigDecimal (a deftype: an unscaled BigInt and a decimal exponent, canonical with no trailing decimal zero, so `1.0M` and `1M` are one value): make, compare (two values, or one against a double taken apart as m * 2^k, the exact comparison native makes), nearest-even float64. Exact where native's big.Float holds 128 bits, so a literal past about 38 significant digits is kept here and rounded there (D233). The wasm runtime loads it (row 2) as its BigDecimal value (rt/wasm/numtower.lg). |
