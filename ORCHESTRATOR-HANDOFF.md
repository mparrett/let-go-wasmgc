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

## In flight right now
- P2.12 variadic ABI (src/): agent id `ab960d47b2add1ad6`. Done when
  `checks/run.sh P2.12` exits 0 and gate 1 + bench-fib stay green.
- P2.13 runtime seams (rt/): agent id `ab89d6b180ef48a7e`. MapSeq/SetSeq
  kind (R5), `f64-neg` intrinsic, D74 raise sweep, review2 refresh.
  Done when `checks/run-intrinsics-native.sh` and `checks/run-review2.sh`
  are green.
  (Resume either with SendMessage to that id if it stalls >45 min with no
  file writes under its dir.)

- Perf investigation (read-only, model fable): agent id `af09b08ef400b738d`.
  Requested by Matt via the coordinator session (`uds:/tmp/cc-socks/47061.sock`,
  2026-10-01 ~11:10). Deliverable `corpus/perf-report.md`; I adopt only
  high-benefit/low-risk items (as D-entries/rows), record the rest.
  Also agreed: Sonnet for mechanical corpus/table items from now on.

## Next in queue (after P2.12 releases src/)
1. P3.2: driver resolves xsofy namespaces (`-source-paths`
   /Users/matt/projects-new/3p/xsofy), compiles `corpus/dump-world.lg`,
   `checks/world-parity.sh 20` → 20/20 MATCH. Needs D97/D100 imports
   emitted (term done; `env.emit`/`env.url_param` not yet).
2. P4.1-backend: emit `env.emit`/`env.url_param`; move
   `corpus/host/pending/term-demo.lg` out; then an xsofy bundle under
   `checks/browser-boot.sh --xsofy` reaching title + map (P4.2 lane 5 via
   zz-determinism-probe.mjs, P4.3 size/boot table).
3. P2.3 / P2.GATE: `checks/run-tests.sh` over `corpus/core-tests.txt`
   (≥ 90% of 273 deftests) once variadics land.
4. Then the Phase 2/3/4 gates in order; Phase 4 gate = campaign finish line.

## State summary (2026-10-01 10:50)
- Phase 1: GATE PASSED (D62), review fixes P1.7 landed (D92–D96).
- Phase 2: runtime complete under native lg (114 tests / 34k asserts);
  compiled through the backend (D75–D78); oracle corpus 13/14 MATCH
  (R5 pending in P2.13); twins: shared 0/91, xsofy 0/143 missing.
- Phase 3: reader (P3.0) and xsofy natives (P3.1) done; P3.2 not started.
- Phase 4: host (P4.0) + shell adapter (P4.1 host half) done; no COI needed
  (D91); depth risk closed (D99).
- Internal dossier of upstream-worthy findings:
  `docs/project_incoming/letgo-upstream-findings-from-lower-wasm-2026-10-01.md`.
