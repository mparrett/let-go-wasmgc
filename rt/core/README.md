# rt/core — libraries every target shares

Plain Clojure, not the runtime dialect: no intrinsics, no IR forms, and no
load-order table. A file here is an ordinary library, found on the source
path (`rt`) by its namespace (`core.<name>` in `rt/core/<name>.lg`), and
compiled the way a program's own libraries are, so the wasm and llvm
targets, and native lg, run the same source.

| File | Namespace | What it is |
|---|---|---|
| `bignum.lg` | `core.bignum` | BigInt and Ratio (deftypes; 32-bit limbs in an int-array, sign apart): parse/print, add sub mul, quot rem mod (let-go's) and ediv emod (big.Int's Euclidean), gcd, compare, nearest-even float64, and `simplify` (let-go's MaybeSimplifyRatio). Nothing calls it yet. Tested against native lg by `corpus/intrinsics/bignum_test.lg`. |
