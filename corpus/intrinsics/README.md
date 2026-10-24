# corpus/intrinsics

Topics: `corpus:runtime`.

The runtime's own tests, run under native lg before anything is compiled: one `*_test.lg` per `rt/wasm` namespace (core, maps, sets, vectors, seqs, strings, reader, eval, emit), plus `bignum_test.lg` for `rt/let-go/lang`'s BigInt and Ratio, checked against native lg's values. Run by `checks/run-intrinsics-native.sh`.
