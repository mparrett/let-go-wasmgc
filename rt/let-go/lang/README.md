# rt/let-go/lang — `let-go.lang.*`, shared by every target

let-go's core types live in its VM: Go types in `pkg/vm`, named
`let-go.lang.*` (`let-go.lang.BigInt`, `let-go.lang.Ratio`, ...). The
compiled targets have no Go host, so their versions of that layer are
written in Clojure and live here under the same name, ready to sit beside
`pkg/vm` when this project merges into let-go. `let-go.core` (lg's
user-facing extras) and `core` (clojure.core) are not this layer.

A file here is plain Clojure, not the runtime dialect: no intrinsics, no IR
forms, no load-order table. It is an ordinary library, found on the `rt`
source path by its namespace (`let-go.lang.<name>` in
`rt/let-go/lang/<name>.lg`, the hyphenated path let-go's resolver tries
first), so the wasm and llvm targets, and native lg, run the same source.

| File | Namespace | What it is |
|---|---|---|
| `bignum.lg` | `let-go.lang.bignum` | BigInt and Ratio (deftypes; 32-bit limbs in an int-array, sign apart): parse/print, add sub mul, quot rem mod (let-go's) and ediv emod (big.Int's Euclidean), gcd, compare, nearest-even float64, and `simplify` (let-go's MaybeSimplifyRatio). Nothing calls it yet, and it does not yet compile as a library on either target (wasm lowers no `.-field`; llvm refuses a def constant used as a value). Tested against native lg by `corpus/intrinsics/bignum_test.lg`. |
