# ORC jank baseline, 2026-10-16

Pre-integration census against pinned let-go `e9789b7d53`, LLVM ORC, `--no-rtlib`. Session 72536 completed in 2772.5 seconds with `P=3`: 114/241 files MATCH, 114/242 deftests passing, no skips. This is a diagnostic census with `--bar 0`, not a passing compatibility gate.

Source was frozen throughout. This predates the integrated boolean equality, bit operations, callable predicates, large function-value calls, variadic equality and program type expansion fixes. It includes the earlier reader/namespace and qualified-test fixes.

Cause labels are heuristic: 19 compile failures, 1 numeric-labelled failure, and 107 other mismatch files. Many numeric omissions appear as runtime errors within the mismatch group; the numeric label is not a complete count. Full assertion counts and first failures are in `results.tsv`.
