# corpus/intrinsics

Topics: `corpus:runtime`.

The runtime's own tests, run under native lg before anything is compiled: one `*_test.lg` per `rt/wasm` namespace (core, maps, sets, vectors, seqs, strings, bignums, reader, eval, emit) checked against native lg's values. Run by `checks/run-intrinsics-native.sh`.
