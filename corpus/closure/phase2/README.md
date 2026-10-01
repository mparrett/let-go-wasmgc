# corpus/closure/phase2

Lines moved out of `../closures.lg` at P1.3 (2026-10-01) because each needs a
Phase-2 runtime piece, not closure support. `run-corpus.sh corpus/closure`
does not descend here; re-merge these into `closures.lg` (or point a Phase-2
row at this dir) once the pieces land. `closures-phase2.lg.expected` is the
native snapshot.

| original line | label | needs |
|---|---|---|
| 13–14 | `per-iter` | vector literal, `conj`, `mapv`, vector printing (P2 collections). The capture shape itself is covered by `../loop-capture.lg` |
| 25–27 | `permute` (`swap-loop`) | vector result `[a b]` |
| 28–29 | `two-exit` | vector arg, `count`, `nth`, vector result with keywords |
| 31–33 | `try` (`risky`) | non-empty map literal `{:x x}` in `ex-info`, keyword invoke `(:x ...)` |
| 34 | `finally` | atom holding a vector, `swap! ... conj`, printing a vector |
| 35 | `nested-throw` | `risky` (map literal in a defn makes the whole program uncompilable) |
