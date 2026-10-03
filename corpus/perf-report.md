# Check/gate wall-time report (2026-10-01, 11:10–12:00 PDT)

Read-only investigation of why verification is slow on this campaign and what to
change. Nothing under `src/`, `rt/` or `checks/` was edited; every measurement ran
in a scratch export of HEAD `6f107d7` (the live tree was mid-edit and its driver
failed to load for part of the hour). Load averages are quoted with every number
because they dominate: the same check varied **5.8×** with load alone during this
hour. Snippets live in `$SCRATCH` =
`/private/tmp/claude-501/-Users-matt-projects-new-3p-joint-xsofy/fca6f592-886f-4b90-9538-46a9d7127210/scratchpad/perf/`.

## Headline

1. **The machine is oversubscribed, and macOS load average overstates it.** At the
   moment load read 32, there were 5 `lg` processes and 1 headless-Chromium GPU
   process at ~100% CPU each: ~6 cores of real demand on 8 cores (4 P-cores). Each
   `lg` is a Go binary with 8 runnable GC threads, so three agents' gates read as
   load 25–47. Real CPU cost of a check is stable (driver: 11.5 s CPU at load 6,
   13.4 s CPU at load 16) while wall is not (8.1 s → 26 s). More parallelism per
   script without a machine-wide cap makes this worse, not better.
2. **Agent wall time ≠ machine time.** 6.1 h of 13.7 h was agents polling in
   `until … sleep` loops; no script change recovers that, only the harness pattern
   (§5). The remaining 7.6 h of machine-bound time splits roughly: oracle compiles
   (the driver is >98% of an oracle program's time; wasm-tools 0.15 s, node 0.2 s,
   native lg 0.03 s), the census, the native tier, and the rtlib rebuilds that
   every scratch tree copy pays separately (six `.rtlib` copies exist under the
   scratchpad right now, 45–175 s each to build).
3. `fseventsd` at 98% did not reproduce (0–8% live over 3 samples; 3% lifetime
   average). Spotlight does not index `dev/lower-wasm` or `/private/tmp` (mdfind
   returns 0 items for both). The churn that exists is agents' tree copies in the
   scratchpad (671 files written in 15 min by one agent's `cp -r`), not the checks.

## Recommendation table

| # | Change | Wall saving per typical item | Per campaign-hour | Fidelity risk | Cost | Verdict |
|---|---|---|---|---|---|---|
| 1a | `run-corpus.sh` parallel, **P=3**, per-program captured output, serial summary (`$SCRATCH/run-corpus-par.sh`) | corpus/wasm 14 programs: median 202 s → 96 s (2.1×; 229 → 85 s in the quieter rep); P1 gate's 126 oracle programs ≈ 17 min → ~8 min | ~10–15 min/h of the oracle-bound share | **none** — output byte-identical at P=1..4 (md5 equal across all 8 runs); rtlib build is atomic (tmp+rename) and pre-warmed once | small | **adopt** |
| 1b | Machine-wide slot pool for heavy steps (`$SCRATCH/sem.sh`, `LW_SLOTS=4`) wrapped around oracle/census/native workers, shared by all agents | converts 3–6× load slowdowns into queueing: native tier 525 s @ load 29–47 vs 90 s @ load 10 | largest machine-side lever; est. 20–40% of machine-bound time while ≥2 agents gate | **none** (ordering/timeouts only; dead-holder reclaim) | small | **adopt** (prerequisite for 1a/6/7 being net positive) |
| 1c | `gate.sh` rows concurrently, -j2, logs kept per row (`$SCRATCH/gate-par.sh`) | gate 1: rows mostly oracle-bound → ~1.6× on top of 1a; also no "rerun to see why it failed" | 5 min/h | **none** (same rows, same exit rule; output kept, not discarded) | small | adopt after 1a+1b |
| 2 | `checks/affected.sh`: diff → minimal row set (`$SCRATCH/affected.sh`) | corpus/checks/host-only items (7 of 29): 1–4 rows instead of a phase gate; src-only items skip the native tier (120–525 s); rt-only items already skip the census (its mtime key reads only `src/`) | 3–8 min/h | **low** — static table; a missed input = a stale row, so gates stay full | small | **adopt** as advisory (implementer runs affected rows; gates unchanged) |
| 3 | `checks/attest` records; orchestrator trusts slow rows for the same tree hash (`$SCRATCH/attest.sh`) | skips the second run of the native tier (2–9 min) on the 12 rt items and of run-tests/world-parity/browser-boot later; oracle rows stay rerun (cheap at P=3) | 2–5 min/h | **medium** — forgeable in principle; mitigated by orchestrator-computed tree hash + lg hash + fast rows always rerun + spot-check of one sub-unit | medium | **defer** until 1a–1c land; adopt only for the slow rows |
| 4 | fsevents/Spotlight: `.metadata_never_index`, relocate caches | not measurable now (daemon at 0–8%) | ~0 | none | small | **reject** as a perf fix; keep the hygiene items (shared rtlib dir, mktemp leak) |
| 4b | Shared content-addressed rtlib dir (`LW_RTLIB_DIR`, e.g. `/tmp/lw-rtlib`) so tree copies reuse one build | 45–175 s per agent per tree copy (6 copies exist today) | 3–5 min/h | **none** — the key is a hash of the exact sources | small (one `def` + `mkdir`) | **adopt** (orchestrator edit to `src/lower_wasm.lg` line 2995) |
| 5 | Polling → `run_in_background` + completion notification; AGENTS.md rule 8 text below | 6.1 h of 13.7 h agent wall (45%) | 27 min/h | none | none | **adopt** |
| 6 | Census per-file sharded, P=4 (LPT by TSV `ms`), content-hash key instead of mtime | fresh census 23.7 min of unit time → ~6 min (xsofy 3.4 + legmacs 2.5 LPT bound; per-process floor 2–3 s); paid on each of the 10 src items | ~6 min/h | **none** (compile-only, per-unit, TSV rows merged in idx order; summary unchanged) | medium | **adopt** |
| 7 | Native tier per test file, `xargs -P 4` | measured 182 s at P=4 (load 25) vs 525 s one-process (load 29–47) and 349 s per-file sum; LPT bound ≈ 95 s (max file seq 86 s); startup floor 2.0 s × 11 files = 6% overhead | 3–6 min/h | **none** — per-file pass sums equal the one-process run (34 281 = 34 281); the deftest-count guard becomes per file | small | **adopt** |
| 8 | `GOMAXPROCS=2/4` on lg | no signal (12.6–30 s all settings, interleaved ×3 at load 26–47) | 0 | none | none | **reject** |

"Typical item" = one row run by the implementer + the orchestrator's rerun + a
phase gate when the row is in a gated phase. Campaign-hour figures assume the
measured mix (31 items in 13.7 h of tool wall) and are estimates; the per-item
columns are measured unless marked LPT (bound from per-unit times).

## Measurements

All in the HEAD export unless noted. `lg-4e76921230`. Load = 1-min average at start.

**Oracle program breakdown** (vectors.lg / maps.lg):

| step | wall | CPU | load |
|---|---|---|---|
| driver, rtlib cold (first run builds it) | 45.4 s | 60.8 s | 5.5 |
| driver, rtlib warm | 8.1 s | 11.5 s | 5.8 |
| driver, rtlib warm | 26.0 s | 13.4 s | 15.7 |
| wasm-tools parse (1.6 MB wat → 281 KB) | 0.15 s | | 15.7 |
| node run | 0.21 s | | 15.7 |
| native lg | 0.03 s | | |

**rtlib build race**: `.rtlib` removed, three drivers started together: all three
exit 0 after **175 s** (vs 45 s for one), identical `.wat` md5, one
`rtlib-cf5351a4.edn` left (load 5.9 → 23.9). The write is `spit tmp` +
`os/rename`, so concurrent builders cannot corrupt the file; the prune only
removes files with *other* keys. Cost is CPU only — which is why every parallel
script must warm the cache once before fanning out (both scratch scripts do).

**corpus/wasm (14 programs), `run-corpus-par.sh`, outputs md5-identical across all runs**:

| P | rep 1 wall (load at start) | rep 2 wall (load) |
|---|---|---|
| 1 | 229 s (21.3) | 175 s (31.3) |
| 2 | 90 s (18.1) | 102 s (21.2) |
| 3 | 85 s (18.5) | 106 s (26.4) |
| 4 | 76 s (19.6) | 131 s (17.7; overlapped the native-tier P=4 run below) |

Medians: P=1 202 s, P=2 96 s, P=3 96 s, P=4 104 s (rep 2 of P=4 contaminated).
Gains stop at P=2–3 because other agents held 3–5 lg processes throughout (each
driver is ~1.4 cores of CPU); P=3 is the cap this report recommends for a shared
8-core laptop, with the pool (1b) making the cap global rather than per script.

**Native tier (D81)**, default tier, HEAD export:

| file | wall | passes |
|---|---|---|
| seq_test | 86.1 s | 1 642 |
| reader_test | 73.8 s | 69 |
| phm_test | 71.4 s | 6 558 |
| phs_test | 37.0 s | 3 131 |
| xsofy_natives_test | 24.3 s | 9 350 |
| pvec_test | 18.1 s | 29 |
| vkind_test | 18.0 s | 124 |
| str_test | 10.6 s | 2 249 |
| core_test | 8.6 s | 10 693 |
| term_test | 0.8 s | 155 |
| intrinsics_test | 0.1 s | 281 |
| **sum (load 12→29)** | **349 s** | **34 281** |
| one process, as `run-intrinsics-native.sh` (load 29→47) | **525 s** | 34 281 |
| D81's figure (load 10) | 90 s | |
| runtime load + one ns (per-process floor) | 2.0 s | |

Time is not where the assertions are: reader (69 passes, 74 s) and seq (1 642,
86 s) dominate, so a per-file split is bounded by the biggest file (~86 s), not by
count. Measured per-file at `xargs -P 4` (load 24.7 → 21.6, overlapping one
other corpus run): **182 s** wall, 11/11 files OK, 34 281 passes — against 525 s
for the one-process run at load 29–47 and 349 s for the per-file sum at load
12–29. The LPT bound (~95 s) needs a quieter machine; the win on this one is
~2–3×.

**Census** (from the committed TSVs' `ms` column, i.e. the 10:16/10:26 run):
xsofy 1 064 units, 825.5 s (13.8 min), largest file world.lg 64 s, largest unit
7.0 s; legmacs 816 units, 592.3 s (9.9 min), largest commands.lg 68 s. legmacs'
wall (10:16:30 → 10:26:28) equals its unit sum, so per-process startup is noise.
LPT over files at P=4: xsofy 207 s, legmacs 149 s → **~6 min vs ~24 min**. One
file alone (`census.lg … main.lg`) costs unit-sum + 2.3 s; at load 29–34 that run
took 164 s for 161 s of units that the cached TSV had recorded as 25 s — the same
6× load effect. Invalidation: the mtime test covers `src/*.lg` + the two census
scripts + the corpus files; `rt/` never invalidates it (good), but any `touch` or
reverted edit of `src/` does, and a tree copy resets mtimes (bad: content-hash the
inputs like the rtlib key does).

**Item → inputs → rows** (`affected.sh --all` is the table). Applied to the 29
non-doc commits of `dev/lower-wasm`: 10 touched `src/` (every oracle row + census
+ bench-fib), 12 touched `rt/` but not `src/` (every oracle row + native tier +
twins + review2; **not** census, refuse or bench-fib: `fib` links no runtime, 1.3 KB
shaken), 7 touched only `corpus/`, `checks/` or `host/` (1–4 rows; `1b822bf`,
`oracle.sh` itself, is the honest outlier at 19). Total 533 row-runs if every
affected row were run, against 29 × 28 = 812 for "run everything" and against the
actual practice of one row + an occasional gate.

**Churn (15-min window, 11:16–11:31)**: `dev/lower-wasm` 9 files (6 `rt/`, 3
`corpus/`); scratchpad 691 files, of which 671 were one agent's tree copy
(`p213/lw/corpus`, 574 `.lg`/`.expected`); `$TMPDIR` 33 files (27 Chromium
profile). `$TMPDIR` also holds 281 leaked `tmp.*` dirs (31 from the last 12 h,
438 MB total) from `KEEP=1` or killed oracle runs. Time Machine includes
the home workspace and excludes `/private/tmp`; the `.rtlib` under the live tree is
therefore backed up (4.3 MB rewritten on every key change), the scratch ones not.

## Ready-to-apply snippets (all in `$SCRATCH`)

- `run-corpus-par.sh` — drop-in for `checks/run-corpus.sh` (same flags minus
  `--update-expected`, plus `-j N`; default 3). Pre-warms the rtlib, fans out with
  `xargs -0 -P`, prints the summary in sorted order. Verified: 8 runs, 4 values
  of P, one md5.
- `sem.sh` — `checks/sem.sh <cmd>`: `mkdir`-based slot pool at `/tmp/lw-sem`,
  `LW_SLOTS=4`, dead-pid reclaim, bounded wait. Verified: two 2 s sleeps under
  `LW_SLOTS=1` take 4 s and leave no slot behind. Wrap the per-program worker in
  `run-corpus-par.sh`, the census shards and the native-tier files with it.
- `gate-par.sh` — `gate.sh` with `-j`, per-row logs under `checks/.gate/<phase>/`,
  one rtlib warm-up. Same row set and exit rule.
- `affected.sh` — static id → inputs table (`--all` prints it); no args = `git
  diff HEAD` + untracked under `dev/lower-wasm`. Verified against the samples in
  the table above and all 29 commits.
- `attest.sh` — records and `--verify`; the spot-check hook is a stub by design
  (one line per row kind), since the verdict is defer.
- 4b is a one-line change for the orchestrator, not a script: in
  `src/lower_wasm.lg` replace
  `(def rtlib-dir (str lw-rt/src-dir "/.rtlib"))` with
  `(def rtlib-dir (let [d (os/getenv "LW_RTLIB_DIR")] (if (seq d) d (str lw-rt/src-dir "/.rtlib"))))`
  and export `LW_RTLIB_DIR=/tmp/lw-rtlib` from `checks/*.sh`. Content-addressed, so
  sharing across tree copies cannot serve a stale library.
- 6 and 7 are edits to `checks/census.sh` and `checks/run-intrinsics-native.sh`:
  census — split the file list into 4 LPT bins by the previous TSV's per-file
  `ms` (fall back to round-robin), run 4 `census.lg` processes under `sem.sh`
  writing `<c>.raw.N.tsv`, concatenate in idx order (pass a per-shard idx
  offset or renumber), then the existing validate + summary steps; native tier —
  replace the single runner call with
  `for f in corpus/intrinsics/*_test.lg; do printf '%s\0' "$f"; done | xargs -0 -P 4 -n1 sh -c '… intrinsics-native-runner.lg "$(grep -c "^(deftest " "$1")" "<ns of $1>" > out/$b'`
  and sum/compare afterwards (the count guard is then per file, which is stricter,
  not looser).

## Text for AGENTS.md rule 8 (proposed; not applied)

> 8. **Never poll.** The harness caps a foreground command at 10 minutes, and a
> check that can take longer (the native tier, a census, a phase gate, world
> parity, browser boot) must not be waited on with `until … sleep` loops: across
> 31 agent runs on 2026-10-01 those loops were 6.1 of 13.7 hours of tool time,
> most of it idle. Start the long check once with `run_in_background: true` and
> a `timeout` sized to the check (gate: 3 600 000 ms), capture its output to a
> file, and **stop**: do other work or end your turn. The harness delivers a
> completion notification with the exit code; act on that. If you must check
> progress, `Read` the output file once — do not loop on it. Where a `Monitor`
> tool exists, prefer it over any `sleep`. Never background anything that
> outlives you (rule 6 still holds): the background job ends with your run.

## Appendix: fidelity notes per change

- **1a/1c (parallel corpus/gate)**: `oracle.sh` and `wasm-run.sh` each `mktemp -d`
  per invocation and share nothing else; `run-corpus.sh`'s only shared file is its
  own `$t/native.out`, which the parallel twin makes per-program. The STALE-EXPECTED
  check runs native lg per program and is unaffected. The one shared mutable
  resource is `src/.rtlib`, covered above (atomic, idempotent, pre-warmed).
  `--both` (`run-tests.sh`) was carried over untested here because the HEAD tree
  has no `_test.lg` in an oracle dir; it uses the same per-program scratch.
- **1b (pool)**: a pool wait that times out runs the command anyway and says so;
  a crashed holder's slot is reclaimed on the next acquire. A smaller `LW_SLOTS`
  cannot change any result, only when it arrives.
- **2 (affected)**: the table is deliberately coarse (prefixes) and errs toward
  running more; the risk is an input added to a check without a table edit, which
  is why gates ignore it.
- **3 (attest)**: the forgery surface is the record file; the orchestrator never
  reads the tree hash from it, it recomputes, so a record can only lie about the
  *result* for a tree it genuinely names. Always rerunning fast rows (everything
  but census, native tier, run-tests, world-parity, browser-boot) and spot-checking
  one sub-unit of a slow row bounds a lie to "one slow row, until the next gate".
- **6 (census shards)**: `census.lg` holds no cross-file state except the `idx`
  counter and the `corpus-nses` set (filled from each file's `ns` form as it is
  read). The set decides `unbound-var` vs `ok` by whether an extern's namespace is
  in the corpus, so each shard must be given the full ns list up front (read all
  `ns` forms first, lower only its share) or the buckets drift. That is the one
  real change in the shard edit.
- **7 (native tier per file)**: `test/run-all-tests` with the ns regex is per
  invocation already; the files share only `rt/`. Per-file counts: 14/12/11/8/4/
  7/11/20/8/2/17 = 114, equal to the one-process `tests=114`.
