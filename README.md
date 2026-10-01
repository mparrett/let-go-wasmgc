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
- `corpus/` — materialised inputs: `scalar/` (let-go's fib, tak, loop-recur),
  `closure/closures.lg` (passes under native lg, 2026-09-30), `core-tests.txt`
  (44 let-go test files / 273 deftests selected by `select-core-tests.sh`,
  rerun when let-go moves), `dump-world.lg` (the Phase 3 canonical world dump:
  reproducible, 0 opaque values, ~0.7 s and ~21 KB per 60-turn world under
  native lg on 2026-09-30).
- `STATUS.md`, `DECISIONS.md` — created by the orchestrator at P1.0; the
  only two files it owns besides the plan.
