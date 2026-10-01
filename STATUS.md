# STATUS (orchestrator-owned; one line per item)

| item | state | by | note |
|---|---|---|---|
| P1.1-corpus | done 2026-09-30 | opus | 42 programs / 8430 lines / 314 error lines; regen byte-identical; div-* skipped (D15); blocked on P1.2 for try |
| P1.0 | done 2026-09-30 | opus | run.sh P1.0 MATCH; scalar 4/4; verified by orchestrator |
| P2.2-corpus | done 2026-09-30 | opus | 201 rows; lg hash == vm.HashValue on all; SPEC.md; quirks H1–H5 |
| P2.1-ref | done 2026-10-01 | opus | 42 intrinsics; 16 tests/310 asserts; pvec to shift 15; dialect check; verified |
| P2.4-corpus | done 2026-10-01 | opus | 14 programs/2785 expected lines; SPEC; bug M1; --native green |
| P1.2 | running | opus | try/throw/tail-call; starts with a break-P1.0 pass |
| P2.4-hamt | running | opus | HAMT in the dialect over intrinsics, order parity vs native |
| P2.5-native | running | opus | seqs in the dialect (list, cons, lazy, chunked, range, reduce) |
