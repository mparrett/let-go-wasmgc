# Progress — 2026-10-03

## Done
- Read README.md, docs/READING-GUIDE.md and docs/LINEAR-TARGET-SPEC.md in order.
- Branch `linear-target-m1`; draft PR https://github.com/mparrett/let-go-wasmgc/pull/1 .
- Target/cache, frozen GC guard, shared representation, numeric module and leaking allocator are pushed (2026-10-03).
- All census families, cast branches, stack operands and owned host buffers are pushed through `fe58ec9`; runtime-helper selection is pushed as `d29334f`. GC byte checks and publish CI passed (2026-10-03).
- D172-D178 record nominal headers, representation placement, cache variance and safe host-buffer ownership (2026-10-03).
- Production runner and README are pushed as `bed5d29`; helper-size evidence is pushed as `b947e19` (2026-10-03).

- P8.6: 4/4 MATCH (2026-10-03).

- P8.7: 40/40 MATCH (2026-10-03).

- P8.8: 16/16 MATCH (2026-10-03).

- P8.9: 13/13 MATCH (2026-10-03).

- P8.10: 4/4 MATCH (2026-10-03).

- Final GC gate 1: 8 rows passed with LW_ATTEST=0 (2026-10-03).

## In progress
- Active final-gate exec session: 75758; poll it before starting another gate. Output: /tmp/linear-m1-final-gate-1.log and /tmp/linear-m1-final-gate-7.log (2026-10-03).
- Representation families, cast refinements, host twins and runner are pushed with GC byte identity green (2026-10-03).
- Exact next command (2026-10-03): `LW_ATTEST=0 checks/gate.sh 7`
- Corpus rows are acceptance checks, not current MATCH claims (2026-10-03).
- Final GC gates are running after every required linear corpus passed (2026-10-03).

## Open questions
- Original runtime cache omits variadic dispatch state on restore; reported in the PR, the team is investigating. Keep GC output unchanged.
- Required linear corpora and helper-size measurement passed; final GC gates remain pending (2026-10-03).
