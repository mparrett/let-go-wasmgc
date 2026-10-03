# STATUS (orchestrator-owned; one line per item)

These records were kept while the backend was built inside a larger workspace. They cite the campaign's plan (D1–D9), round notes (ROUND2–4), the handoff, INVENTORY and TOUR; those are working notes that stayed behind and are not in this repository. D-numbers cited from the code resolve here.

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
| P2.GATE | PASSED w/ 1 named limit 2026-10-01 20:21 | — | 13/14 rows; P2.3 = to-array deftest (D122) |
| CAMPAIGN | COMPLETE 2026-10-01 | — | gates 1,2*,3,4 closed; see ORCHESTRATOR-HANDOFF.md |
| P5.0 | done 2026-10-01 | — | quality baselines in corpus/quality/2026-10-01 |
| P5.5 | done 2026-10-02 | runner | affected table already maps src/+rt/ → P3.2, P4.2; row check fixed (SIGPIPE) |
| P5.1/P5.2 | dispatched 00:05 | opus | 8 remaining deftests; to-array, sorted kinds, set-test reflection; slurp + macro-atom → SKIP |
| P5.3 | dispatched 00:05 | opus | corpus/wasm/gaps, rt/ only |
| P5.R | dispatched 00:05 | opus | read-only, corpus/review3 |
| P5.4 | in progress 00:05 | runner | checks/attest.sh |
| P6.2 | measured 2026-10-02 00:50 | runner | 152/373 deftests, 9/30 files on the round-1 tree; table corpus/legmacs-tests-results.tsv; blockers → P6.1 scope (ROUND2.md) |
| P5.R | done 2026-10-02 01:20 | opus | corpus/review3: 51 oracle programs 25 MATCH, 12 bugs ranked; xsofy-critical claims HELD (map order, hash, closures); fix rows P5.6–P5.11 filed |
| P5.1 | done 2026-10-02 02:35 | opus | 271/273, 44/44, 2 named skips; verified by rerun (58fb3a7) |
| P5.2 | done 2026-10-02 02:35 | opus | P2.3 2/2; to-array/object arrays (58fb3a7) |
| P5.3 | verifying 02:50 | opus+runner | rt half in 58fb3a7 (2/4); src patches A/B/C applied, run.sh P5.3 running |
| P5.6/P5.7 | dispatched 02:20 | opus | regex literal/POSIX/backtracking; math-round trap, dissoc!, array-map msg |
| P6.0+P5.8 | dispatched 01:25 | opus | legmacs twins + review3 unbound natives, rt/ only |
| P5.6 | done 2026-10-02 04:20 | opus | fix-regex 3/3: Go-compiled program + bit-state backtracker, POSIX classes, literal regex stays a regex; verified by rerun |
| P5.7 | done 2026-10-02 04:20 | opus | fix-twins 3/3: saturating float→long, dissoc! variadic, array-map message; verified by rerun |
| P5.10/P5.11 | dispatched 03:15 | opus | test shim + --corpus counter vs native |
| P6.0 | verifying 05:40 | opus+runner | natives.lg 40+ twins, --skip; src patch applied; run.sh P6.0 running |
| P5.8 | verifying 05:40 | opus+runner | named no-twin error + twins; run.sh P5.8 running |
| P5.12 | filed 05:40 | — | loop-shadow miscompile repro (native 10 10 7) |
| P5.9 | dispatched 04:40 | opus | reader meta, var/regex stand-ins (type, symbol?, var?, deref) |
| P6.0 | done 2026-10-02 06:10 | opus | MISSING 0 / SKIPPED 6 / REACHED 146; legmacs-twins 10/10; verified by rerun |
| P5.8 | done 2026-10-02 06:10 | opus | fix-natives 1/1; no-twin named error; verified by rerun |
| P5.10 | done 2026-10-02 06:15 | opus | 3/3 PASS after P5.8's error landed; verified by rerun |
| P5.11 | done 2026-10-02 06:15 | opus | counter vs native; core tests stay 271/273; verified by rerun |
| P5.9 | done 2026-10-02 06:40 | opus | fix-meta 5/5; verified by rerun |
| P5.4 | done 2026-10-02 07:20 | runner | first gate.sh 2 10m29s all 14 ok (P2.3 included); second run 1 s, 13 attested, same result |
| GATE 2 | re-run 2026-10-02 07:15 | runner | 14/14 ok on af7e1d0, no named limit left (D127's P2.3 limit closed by P5.2) |
| P6.3/P6.4/P6.5 | built 2026-10-02 08:10, red | opus | all stop at the P6.1 *err* binding blocker; host half proven on a stand-in (boot 310 ms, echo 19 ms) |
| P5.12 | verifying 09:40 | opus+runner | ir.build/build-loop upstream bug worked around; diff applied |
| P6.1 | verifying 09:40 | opus+runner | 816/816 in scratch; dynvars/arity/nsinit corpora; diff applied, run.sh P6.1 running |
| P6.R | dispatched 09:45 | opus | read-only, corpus/review4, frozen copy incl. P6.1 |
| P6.R | done 2026-10-02 10:50 | opus | review4: 11 bugs, rows P6.6-P6.8 filed; xsofy rows held |
| P6.2 | measured 2026-10-02 11:00 | runner | 252/373, 24/30 on 1f51b18; #bar 252; limit-adjusted ceiling 262 (eval + go/future/promise = Phase 7) |
| P6.3 | done 2026-10-02 11:40 | opus | legmacs-parity 5/5 MATCH (legmacs 187fea2), module 1.23 MB raw / 343 KB opt |
| P6.4/P6.5 | red 11:40 | — | boot dies at install-spawn-tracking! (alter-var-root of native #'future*); rt half → P6.7, src half → P6.8 (messaged) |
| P6.8 | done 2026-10-02 12:50 | opus | fix-backend 9/9; verified by rerun; rooted natives for legmacs' spawn tracking |
| P6.6/P6.7 | verifying 13:20 | opus+runner | rt traps/twins + bound-fn src diff applied; batch running |
| P6.6 | done 2026-10-02 13:40 | opus | fix-traps 4/4; verified by rerun |
| P6.7 | done 2026-10-02 13:40 | opus | fix-twins 11/11, P6.0 MISSING 0/156 on the regenerated reach list; verified |
| P6.4 | done 2026-10-02 13:40 | opus | legmacs boots in the browser: bootMs 264, echoMs 17, resizeMs 31, no COI |
| P6.5 | done 2026-10-02 13:40 | opus | corpus/legmacs/size-boot.md; stock lane size-only (cannot boot) |
| P6.2 | bar 262 2026-10-02 13:40 | runner | ceiling after P6.6; gate 6 verifies |
| CLOCK NOTE | 2026-10-02 04:15 PDT | runner | the times I wrote in the round-2 rows above (from "dispatched 00:05" through "13:40") are wrong by roughly +9 h: round 2 started 2026-10-01 22:30 PDT, not 00:05, and the "13:40" rows landed at 04:09 PDT on 10-02. Git commit times are authoritative; D128–D136 were written 2026-10-01 22:30–23:40 PDT although dated 10-02. |
| COST (through 04:12 PDT, before the gate runs) | 2026-10-02 | runner | see the Round-2 cost table below (method: the summary doc's tally over this session's JSONL + subagents/, since 2026-10-01 22:25 PDT) |

## Round-2 cost (list prices, same assumptions as the round-1 tally; through 2026-10-02 04:12 PDT, before the gate runs)

| model | turns | output | cache read | cache write | ≈ cost |
|---|---|---|---|---|---|
| claude-fable-5-1 | 441 | 0.28 M | 0.12 B | 0.8 M | ≈$209 |
| claude-opus-5-5 | 2650 | 0.05 M | 0.53 B | 11.7 M | ≈$1,018 |
TOTAL ≈ $1,227
| GATE 5 | PASSED 2026-10-02 05:11 PDT | runner | 14/14 with LW_ATTEST=0 (first run: P5.4 self-test could not run under the decision env; fixed) |
| GATE 6 | PASSED 2026-10-02 05:21 PDT, ROUND 2 FINISH LINE | runner | 10/10 with LW_ATTEST=0; gates 1–4 green the same morning (1: 8/8 05:19, 2: 14/14 04:40, 3: 3/3 04:29, 4: 4/4 04:44); D158 |

## Round-2 cost, final (list prices, same assumptions as the round-1 tally; 2026-10-01 22:25 to 2026-10-02 05:25 PDT; Opus output tokens are undercounted in the subagent transcripts as in round 1)

| model | turns | output | cache read | cache write | ≈ cost |
|---|---|---|---|---|---|
| claude-fable-5-1 | 484 | 0.33 M | 0.13 B | 0.9 M | ≈$242 |
| claude-opus-5-5 | 2650 | 0.05 M | 0.53 B | 11.7 M | ≈$1,018 |
| **total** | | | | | **≈$1,259** |

## Round 3, Track A (Phase 7 eval), started 2026-10-02 ~08:00 PDT (git times authoritative)

| item | state | by | note |
|---|---|---|---|
| P7 rows | appended 2026-10-02 | runner | items.tsv P7.0-P7.GATE exit 2 until built; affected table; seam in ROUND3.md |
| D159 | done 2026-10-02 | runner | os/getenv reaches the host; XSOFY_DEV=1 under node (a small ask from us) |
| A: rt/wasm/eval.lg | running | opus | closure-compiling evaluator, core table, core macros, registry ns/vars, reader code forms, corpus/eval |
| B: program table | running | opus | backend emits install-program-table! when eval is reached; *ns* route; program macros as hidden fns; corpus/eval/program |
| P7.5 | green 2026-10-02 09:00 (on B's in-flight src) | runner | eval-hosts.sh PASS: node, Chromium, legmacs C-x C-e => 42; playground legmacs.wasm + :8261 refreshed for our test drive |
| P7.0 | done 2026-10-02 (D160) | opus A | corpus/eval 10/10, native tier 122 tests, P2.1/P4.2 green; program/ waits for B |
| C: legmacs wiring | running | opus | P7.2 script 6, P7.1 ledger + bar, P7.3 prep, evaluator gaps in rt |
| P7.1 | done 2026-10-02 (D162) | opus C | 28/30 (repl 7/7, letgo 21/23); whole suite 316/373, bar raised |
| P7.2 | done 2026-10-02 (D162) | opus C | script 6 byte-identical |
| P7.3 | done 2026-10-02 (D162) | opus C | comment.lg loaded by eval defines comment-dwim; defcommand expands in-module |
| B: program table | done 2026-10-02 (D161) | opus B | table +24 KB brotli, eval.lg +23 KB; xsofy byte-identical |
| P7.6 | done 2026-10-02 (D163) | opus B | LW_NO_EVAL=1: legmacs 166 KB -> 120 KB brotli, eval-free modules unchanged |
| P7.4 | done 2026-10-02 11:30 | runner | legmacs bundle 173 KB brotli (round 2: 119 KB module, bundle not recorded with eval), boot median 378 ms at load ~20 (round 2: 264 ms); xsofy 430,781 opt / 115,109 brotli (round 2: 417 KB / 112 KB; inc/dec value fix), title 4571 ms |
| P7.R | running | opus R | adversarial review, corpus/review5 |
| P7.7 | done 2026-10-02 (D165) | opus | 22/22 evaluator fixes |
| P7.8 | done 2026-10-02 (D164) | opus | 7/7 + 1/1 runtime fixes |
| P7.9 | done 2026-10-02 (D166, D167) | opus B + runner | 7/7 backend fixes; _main ns tag regression caught by gate 5 and fixed |
| P7.GATE | GREEN 2026-10-02 ~20:05 (D168) | runner | gate 7 11/11; gates 1-6 8/13/3/4/14/10, all LW_ATTEST=0 on d953b83 |
| P9.0 | done 2026-10-03 (D181) | runner | rtlib cache transparent: cold/warm byte-identical on the D181 regression (differed before the fix) |
| D182 | done 2026-10-03 | runner | (println os/args) MATCH on the GC lane; regression corpus/scalar/os-args.lg under P1.1; run.mjs argv[0] = lg path |
| REPL page | done 2026-10-02 | runner | host/repl.html, 285 KB opt / 77 KB brotli, 13 examples, :8262 in lw-play |
| cost round 3 | estimate 2026-10-02 | runner | ~1.9 M subagent tokens (9 Opus + 1 Sonnet dispatches) + runner; list-price estimate ~$1.5k (round 2 ~$1.26k, round 1 ~$4.5k); session total 558 M in / 1.45 M out across rounds 2-3 |

## Linear target — 2026-10-03

| item | state | note |
|---|---|---|
| P8.0 | PASS | 2026-10-03: frozen pre-change scalar and eval GC binary guard; compare default and explicit GC |
| P8.1 | PASS | 2026-10-03: driver target selection, precedence and isolated runtime cache keys; unfinished linear output refused by op name |
| P8.2 | PASS | 2026-10-03: linear module skeleton and bump allocator; validate with GC disabled |
| P8.3 | PASS | 2026-10-03: ref.cast, struct.get, ref.null, ref.test and struct.new probes validate with GC disabled; wazero prototypes exercise field reads and caught named errors |
