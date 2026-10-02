# Orchestrator handoff (written 2026-10-01 ~10:50 PDT, before a possible context compaction)

Read this first after compaction. Durable state is on disk: `STATUS.md`
(per-item state), `DECISIONS.md` (D1–D105, binding), `checks/items.tsv`
(definition of done per item), `FINDINGS.md`, git log of
`~/projects-new/3p/joint-xsofy` (every landed item is one commit, latest
6f107d7 "P2.11").

## Standing rules for this campaign (from Matt)
- Skunkworks: nothing pushed, no gh, no PR, no issue, until Matt and I talk
  (he said "nothing gets PR until we chat tomorrow", 2026-09-30 evening).
  Commit locally to joint `main` after verifying each item.
- Loop: `/loop We work to completion but nothing gets pr until we chat
  tomorrow` (dynamic mode, ScheduleWakeup 1500 s fallback; agent
  notifications are the wake signal).
- At most 3 Opus subagents at a time (memory rule). Items touching `src/`
  run sequentially; `rt/` items can run beside one `src/` item.
- Every agent reads `AGENTS.md`; I verify each report by running the row's
  check myself (`checks/run.sh <id>`) before committing; then record new
  D-numbers in DECISIONS.md, update STATUS.md, commit.
- Pulse claim held: `task:letgo-emit-wasm-campaign` (#303). Release with
  `--outcome handoff` when stopping.

## ROUND 2 STARTED 2026-10-02 00:05 PDT (plan: ROUND2.md; rows P5.*/P6.* in items.tsv)
- Pulse claim #314 `task:letgo-emit-wasm-campaign` held again. Loop prompt:
  `/loop we will work until completion of our objectives but nothing gets pr until after we chat tomorrow`.
- Decisions continue from D128. Round-1 rules unchanged (3 Opus max, src/ one at a time, verify by rerunning the row, commit per item).
- In flight at 00:05: P5.1+P5.2 (opus, owns src/+rt/) agent `a802887eec7e3b717`;
  P5.3 (opus, rt/ + corpus/wasm/gaps, no src/) agent `af3f0ef23d134c3c3`;
  P5.R reviewer (opus, read-only, corpus/review3) agent `a79b16cc200312b2e`.
  Runner builds P5.4 `checks/attest.sh` meanwhile. P5.5 already satisfied (check fixed in 1fc6164).
- 01:25: P5.R DONE (6f35066): review3 filed fix rows P5.6-P5.11. P5.4 mechanism landed (9c72c4a), row waits for a settled tree.
  Third slot now P6.0 + P5.8 twin half (opus, rt/ + checks/native-twins.sh --skip, no src/) agent `aa4d7abc83a06d628`.
  Queue for the src/ slot once P5.1/P5.2 reports: P5.6 regex, P5.9 meta/var stand-in, P5.10/P5.11 test shim + counter,
  P5.7 twins' trap fix, P5.8's named-error half (patch from the twins agent), then P6.1 (5 census blockers + 3 ns-init blockers).
  P6.2 first measurement 152/373 (a11dc4e). NOTE corpus/core-tests-results.tsv is modified in the tree by a legmacs
  run (my mistake); the next P5.1 --corpus run regenerates it; do not commit the legmacs rows under that name.
- Next: P5.GATE, then Phase 6 legmacs (P6.0 natives + P6.1 blockers first; P6.2 needs corpus/legmacs-tests.txt over 30 files).

- 03:15 state: P5.0 P5.1 P5.2 P5.3 P5.5 P5.R DONE (58fb3a7, eeca0fd; D128-D133). P5.4 mechanism in, row needs a
  settled tree (run `LW_ATTEST=0 checks/gate.sh 2` once, then `checks/run.sh P5.4`). In flight: P5.6+P5.7 regex/trap
  (opus, src/lw_ext.lg lw_rt.lg lower_wasm.lg) agent `aedf16da08ce741e3`; P6.0+P5.8 twins (opus, rt/wasm/natives.lg)
  agent `aa4d7abc83a06d628`; P5.10+P5.11 test shim + counter (opus, src/testshim.lg checks/run-tests.sh) agent `a9fde288530c2dafd`.
  Queue: P5.9 (reader meta + var stand-in, src/lower_wasm.lg) after the regex agent; P5.8's named-error src half (patch from
  the twins agent); then P5.GATE (LW_ATTEST=0, gates 5,1,2,3,4); then P6.1.
  Struct change to tell every new agent: `wasm/new Fn` 8 fields, Atom/Volatile 2 (trailing 0) since eeca0fd.

## CAMPAIGN COMPLETE 2026-10-01 20:30 (D127). Nothing in flight. Pulse claim released.

## (historical) In flight at 13:05
- P3.2 xsofy world-gen parity (src/, opus): agent `a94c28a6237679045`.
  Done when `checks/run.sh P3.2` exits 0 (world-parity.sh 20/20).
- P0.1 check speedups (checks/, sonnet): agent `a6f67a916a68a3410`. Done when
  `checks/run.sh P0.1` exits 0 with byte-identical outputs (D106).
- P2.3 measurement (read-only, sonnet): agent `ad8a481f75b8f2e5e`. Report
  `corpus/core-tests-report.md` (pass/273, blockers) → decides P2.GATE work.

## Next in queue
1. P4.1-backend: `env.emit`/`env.url_param` (D100) if P3.2 did not add them;
   term-demo out of pending; xsofy bundle under `browser-boot.sh --xsofy`
   reaching title + map; then P4.2 lane 5 (`zz-determinism-probe.mjs`), P4.3
   size/boot table.
2. P2.GATE: fix the top blockers from the P2.3 report until ≥ 90% of 273.
3. Gates 2, 3, 4 in order; Phase 4 gate = finish line.

## State summary (updated 2026-10-01 17:10)
- PHASE 4 GATE PASSED (D120): the finish line. Remaining: P2.14 (core tests to 90%, agent `ae43ef09041ca0217`), P0.1 (speedups, agent `a6f67a916a68a3410`), then P2.GATE, a campaign summary for Matt, release the pulse claim with --outcome handoff.

## State summary (2026-10-01 10:50)
- Phase 1: GATE PASSED (D62), review fixes P1.7 landed (D92–D96).
- Phase 2: runtime 116 tests / 37.8k asserts; compiled through the backend;
  oracle corpus 14/14 MATCH; variadics landed (D109–D111); twins: shared
  0/91, xsofy 0/143 missing. P2.GATE needs the core-tests number (P2.3).
- Phase 3: reader (P3.0) and xsofy natives (P3.1) done; P3.2 not started.
- Phase 4: host (P4.0) + shell adapter (P4.1 host half) done; no COI needed
  (D91); depth risk closed (D99).
- Internal dossier of upstream-worthy findings:
  `docs/project_incoming/letgo-upstream-findings-from-lower-wasm-2026-10-01.md`.
