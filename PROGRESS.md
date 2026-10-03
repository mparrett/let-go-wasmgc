# Progress — 2026-10-03

## Done
- Read README.md, docs/READING-GUIDE.md and docs/LINEAR-TARGET-SPEC.md in order.
- Branch `linear-target-m1`; draft PR https://github.com/mparrett/let-go-wasmgc/pull/1 .
- Target/cache, frozen GC guard, shared representation, numeric module and leaking allocator are pushed (2026-10-03).
- Census families through array.get are pushed as `97e948c`; default/explicit GC byte checks and publish CI passed (2026-10-03).
- D172-D178 record nominal headers, representation placement, cache variance and safe host-buffer ownership (2026-10-03).

## In progress
- host-twins: imports and quoted output now use allocator-owned payloads; structural buffer checks, target checks and all frozen GC comparisons passed (2026-10-03).
- Exact next command (2026-10-03): `/tmp/linear-m1-remaining.sh`
- Sequential checkpoint script: `/tmp/linear-m1-post-census.sh` (2026-10-03).
- Temporary full-runtime oracle preflight is separate from committed corpus acceptance (2026-10-03).

## Open questions
- Original runtime cache omits variadic dispatch state on restore; reported in the PR, the team is investigating. Keep GC output unchanged.
- Runner, linear oracle corpora, host-buffer twins, README paragraph and final GC gates remain pending.
