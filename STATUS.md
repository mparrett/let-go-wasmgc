# STATUS (orchestrator-owned; one line per item)

| item | state | by | note |
|---|---|---|---|
| P1.1-corpus | done 2026-09-30 | opus | 42 programs / 8430 lines / 314 error lines; regen byte-identical; div-* skipped (D15); blocked on P1.2 for try |
| P1.0 | done 2026-09-30 | opus | run.sh P1.0 MATCH; scalar 4/4; verified by orchestrator |
| P2.2-corpus | done 2026-09-30 | opus | 201 rows; lg hash == vm.HashValue on all; SPEC.md; quirks H1–H5 |
| P2.1-ref | done 2026-10-01 | opus | 42 intrinsics; 16 tests/310 asserts; pvec to shift 15; dialect check; verified |
| P2.4-corpus | done 2026-10-01 | opus | 14 programs/2785 expected lines; SPEC; bug M1; --native green |
| P1.2 | done 2026-10-01 | opus | 16/16; fixed 4 P1.0 bugs (declare, deep recursion, :multi loops, :break target); opmatrix 18/39; verified |
| P2.4-hamt | done 2026-10-01 | opus | phm 580 + phs 136 lines; 19 tests/10481 asserts; vstub removed; SPEC gap D49 |
| P2.5-native | done 2026-10-01 | opus | seq.lg 786 lines, 11 tests/12k asserts, chunk parity, 4 gate programs match natively |
| P1.1-backend | done 2026-10-01 | opus | 44/44 incl. typed probe; hybrid i31 (fib 15.5 ms); verified |
| P2.6-native | done 2026-10-01 | opus | str.lg 1122 lines; 20 tests/2239 asserts; floats 281/281 exact (Go strconv port) |
| P1.3 | running | opus | closures (D36 ABI), var table, unknown-callee calls |
| P2.8 | running | opus | native-twin report tooling |
| P2.9 | running | opus | runtime integration: seq.lg patch, per-kind hooks, slow tier split |
