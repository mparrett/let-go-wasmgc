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
| P1.7 | done 2026-10-01 | opus | 48/48 fixed + 3 refused; tail calls; purity pins; gate green, bench 1.37×; verified |
| P2.1-corpus | done 2026-10-01 | opus | 14 programs, 5 MATCH; F1–F9 → P2.11; variadics → P2.12 |
| P3.1 | done 2026-10-01 | opus | xsofy MISSING 0/135; xxh3 200 vectors; 106 tests; verified |
| P4.0 | done 2026-10-01 | opus | host glue + ABI; hello MATCH in Chromium/node/wasmtime; no COI needed; JSPI depth risk D89 |
| P2.11 | done 2026-10-01 | opus | F1–F9 fixed; corpus/wasm 13/14 with rt patches A/B/C applied by orchestrator; gate green 1.37× |
| P4.1-runtime | done 2026-10-01 | opus | 24 term twins; xsofy MISSING 0/143; depth max 20 (D89 closed) |
| P4.1-host | done 2026-10-01 | opus | real shell boots emitted modules; coalescing; --xsofy-shell green; emit/url_param defined (D100) |
| P2.12 | done 2026-10-01 | opus | $FnV ABI; 9/9 + 3 refused; rtlib 0 lowering failures; bench 1.375; verified |
| P2.13 | done 2026-10-01 | opus | kind 27; f64-neg; raise sweep (~80 sites); 116 tests/37.8k asserts; corpus/wasm 14/14; verified |
| perf | investigated 2026-10-01 | fable | corpus/perf-report.md; D106; P0.1 queued for application |
| P2.1 + P2.11 | GREEN 2026-10-01 | — | checks/run-corpus.sh corpus/wasm = 14/14 |
| P0.1 | done 2026-10-01 | sonnet | all speedups byte-identical; run.sh P0.1 green |
| P3.2 + P3.GATE | PASSED 2026-10-01 | opus | 20/20 (+5/5 autoex, 5/5 descend, 3/3 deep); 313 KB module; verified |
| P2.3 | measured 2026-10-01 | sonnet | 133/273 (49%); blockers → P2.14 (D112) |
| P2.14 | done 2026-10-01 | opus | 265/273 (97%); 38/44 files; gold 3/7; verified via gate 2 run |
| P2.2 | done 2026-10-01 | — | wasm-hash.sh: 201 rows, 0 misses, 11 limits |
| P4.1-backend + P4.3 | done 2026-10-01 | opus | xsofy plays in the real shell; 140 KB brotli; verified --xsofy PASS |
| P4.2 | done 2026-10-01 | sonnet | settle-based lane5; 3/3 IDENTICAL; stock lane was the flaky one |
| P4.GATE | PASSED 2026-10-01 17:05 | — | campaign finish line; verified by orchestrator |
| P2.14 | progress 17:56 | opus | 145/273 measured (blocker 1 done: source paths + load-by-path); blockers 2-8 + regex engine coded in scratch, rebuilding/measuring |
| P0.1 | progress 17:59 | sonnet | steps done: sem.sh pool, run-corpus P=3, gate -j2, native per-file P=4, census sharded P=4 + content-hash key, LW_RTLIB_DIR, affected.sh bash-3.2 fix; serial-vs-parallel outputs byte-identical (corpus/wasm, native, legmacs+xsofy TSV, gate); falsified; remaining: final `checks/run.sh P0.1` in the live tree (census rerun in progress, then gate once); ETA 30 min |
| P2.14 | progress 18:21 | opus | 223/273 (dev tree; blockers 1-7 + stdlib/regex/format fills in); working on the tail: getBytes, quality.*, walk, thrown, replace-fn |
| P2.14 | progress 18:44 | opus | 265/273 projected (subsets on dev tree); ported to src/, running checks/run.sh P2.14 then P3.2 + corpus/wasm |
| P2.14 | progress 18:55 | opus | 265/273, 38/44 files: checks/run.sh P2.14 exit 0; running P3.2, corpus/wasm, gold, falsification done |
| P2.14 | done 19:11 | opus | 265/273 (97%), 38/44 files; run.sh P2.14 exit 0; corpus/wasm 14/14; P3.2 20/20; gold 3/7 |
| P2.4 | GREEN 2026-10-01 | — | 14/14 after array-map twin |
| P2.5 | GREEN 2026-10-01 | — | corpus/seqs 4/4 |
| P2.14 | re-verified 2026-10-01 | — | 265/273, 38/44 on the settled tree |
| P2.7 | GREEN 2026-10-01 (scoped) | — | 2/2 in scope; 10 skipped with reasons |
