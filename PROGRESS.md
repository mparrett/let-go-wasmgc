# Progress — 2026-10-03

## Done
- Read README.md, docs/READING-GUIDE.md and docs/LINEAR-TARGET-SPEC.md in order.
- Branch `linear-target-m1`; draft PR https://github.com/mparrett/let-go-wasmgc/pull/1 .
- Target/cache, frozen GC guard, shared representation, numeric module and leaking allocator are pushed (2026-10-03).
- All census families, cast branches, stack operands and owned host buffers are pushed through `fe58ec9`; runtime-helper selection is pushed as `d29334f`. GC byte checks and publish CI passed (2026-10-03).
- D172-D178 record nominal headers, representation placement, cache variance and safe host-buffer ownership (2026-10-03).

## In progress
- entry-runner: structural execution passed; argv oracle caught missing String box in the host argument twin, now corrected (2026-10-03).
- Exact next command (2026-10-03): `python3 /tmp/linear-m1-corpus-rows.py`
- Sequential checkpoint script: `/tmp/linear-m1-remaining.sh` (2026-10-03).
- Temporary full-runtime oracle preflight is separate from committed corpus acceptance (2026-10-03).

## Open questions
- Original runtime cache omits variadic dispatch state on restore; reported in the PR, the team is investigating. Keep GC output unchanged.
- Runner, linear oracle corpora, README paragraph and final GC gates remain pending.
