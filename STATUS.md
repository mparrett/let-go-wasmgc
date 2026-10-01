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
| P1.3 | done 2026-10-01 | opus | 11/11; $Fn layout D52; atom; error parity; verified |
| P2.8 | tooling done 2026-10-01 | opus | inventory 954; shared MISSING 46/93 (proposed manifest); markers to be applied by P2.9 |
| P2.9 | done 2026-10-01 | opus | one runtime; 23 kinds; real keys; 59 twin markers; shared MISSING 53/93; verified |
| P1.4-6 + P1.GATE | done 2026-10-01 | opus | 4/4 refused; census 0 op errors/0 goto; switch; GATE 1.385× verified |
| P2.7 | done 2026-10-01 | opus | core.lg 1072 lines, 56 twins; shared MISSING 0/91; 80 tests/24.6k asserts; verified |
| P2.1-backend | running | opus | emit intrinsics, compile rt/wasm through the backend, --both |
| P3.0-reader | done 2026-10-01 | opus | 951 inputs 0 mismatch; Go-exact float parse; 7 tests |
| P2.1-backend | done 2026-10-01 | opus | runtime compiles through the backend; rt_wasm.lg MATCH; fib 1.33×; P2.1 bar redefined (D75) |
| review-1 | done 2026-10-01 | opus | 148 probes: 78 match, 11 bugs (5 silent), 2 gaps → P1.7 |
| review-2 | done 2026-10-01 | opus | 2300 seeds; 16 runtime bugs (8 silent) → P2.10 |
| P2.10 | done 2026-10-01 | opus | 15/16 fixed, 1 deferred; vkind_test; 89 tests; verified |
| P1.7 | running | opus | Phase 1 review fixes |
| P2.1-corpus | running | opus | corpus/wasm oracle programs |
| P3.1-runtime | running | opus | xsofy-only natives in the dialect (arrays, math, xxh3, nanotime) |
