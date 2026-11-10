# LLVM reuse evidence

| Scenario | Command | Purpose |
|---|---|---|
| JOURNEY-0001 | `LLVM_RTLIB_REUSE_FULL=1 bash checks/llvm-rtlib-reuse-check.sh` | Real profile A/B/A, executable parity and reuse |
| JOURNEY-0002 | `bash checks/llvm-analysis-reuse-check.sh` | Boxing convergence, mutable templates, enabled/disabled/native parity |
| SCENARIO-0001 | `bash checks/llvm-rtlib-reuse-check.sh` | Source-key invalidation and all three targets' retention policy |
| SCENARIO-0002 | `TEST_DIR=corpus/llvm-rt LW_PAR=1 bash checks/run-intrinsics-native.sh` | Runtime and cache units; sentinel |
| SCENARIO-0003 | `bash checks/gensym-load.sh` | Compiler load remains neutral; sentinel |
| SCENARIO-0004 | `checks/quiet.sh caffeinate -i bash checks/bench-llvm-analysis-reuse.sh` | Controlled five-run compile-time measurements |

Build checks use the shared bench-baton. The quiet timing command owns its own
exclusive lease and must never be nested inside a shared build lease.
