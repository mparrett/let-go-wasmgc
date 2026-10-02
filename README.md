# lower-wasm — campaign scaffold (2026-09-30)

Plan: `docs/project_incoming/letgo-emit-wasm-plan-2026-09-30.md` (skunkworks;
see its first section before writing anything outbound). Probe and prep
measurements: `../emit-wasm-probe/`. P1.0 moves the probe's walker in here.

- `checks/items.tsv` — the work queue and the definition of done: one row per
  item, with the exact command whose exit 0 means done. `checks/run.sh <id>`
  runs one; `checks/gate.sh <phase>` runs a phase. Exit 2 = the check is not
  built yet, which is the implementer's job alongside the feature.
- `checks/oracle.sh` — the single match relation (stdout bytes + exit class +
  normalised first error line). Every "MATCH" in items.tsv means this script.
- Check speed (D106): `checks/sem.sh <cmd>` is a machine-wide pool of
  `LW_SLOTS` (default 4) heavy-process slots under `${TMPDIR:-/tmp}/lw-sem`
  (set `LW_SEM` to one path if agents' TMPDIRs differ); wrap leaves, not
  orchestrators. `run-corpus.sh` (`LW_PAR`, default 3, 1 = serial),
  `run-intrinsics-native.sh` (`LW_PAR`, default 4, one lg per test file, count
  guard per file and in total), `census.sh` (`CENSUS_SHARDS`, default 4; cache
  keyed by a content hash in `corpus/census/<corpus>.key`) and `gate.sh`
  (`LW_GATE_J`, default 2; each row's output kept in
  `${TMPDIR}/lw-gate-<phase>/<id>.log`) fan out through it and print what the
  serial runs printed. `checks/affected.sh` lists the rows a diff touches
  (advisory; gates stay full). `LW_RTLIB_DIR=<absolute dir>` moves the runtime
  library cache off `src/.rtlib` so tree copies on the same sources share one
  build (content-addressed; a build prunes other keys in that dir, so copies
  on different sources evict each other).
- `corpus/` — materialised inputs: `scalar/` (let-go's fib, tak, loop-recur),
  `closure/closures.lg` (passes under native lg, 2026-09-30), `core-tests.txt`
  (44 let-go test files / 273 deftests selected by `select-core-tests.sh`,
  rerun when let-go moves), `dump-world.lg` (the Phase 3 canonical world dump:
  reproducible, 0 opaque values, ~0.7 s and ~21 KB per 60-turn world under
  native lg on 2026-09-30).
- `STATUS.md`, `DECISIONS.md` — created by the orchestrator at P1.0; the
  only two files it owns besides the plan.
