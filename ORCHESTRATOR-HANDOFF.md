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
