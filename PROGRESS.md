# Progress — 2026-10-03

## Done
- Read README.md, docs/READING-GUIDE.md and docs/LINEAR-TARGET-SPEC.md in order.
- Branch `linear-target-m1`; draft PR https://github.com/mparrett/let-go-wasmgc/pull/1 .
- Target/cache, frozen GC guard, shared representation, numeric module and leaking allocator are pushed (2026-10-03).
- Instruction families through ref.is_null are pushed as `59c41d4`; publish CI passed (2026-10-03).
- ref.as_non_null passed structural execution, target checks and all frozen default/explicit GC comparisons (2026-10-03).
- D172-D176 record nominal headers, representation placement, cache variance and safe host-buffer ownership (2026-10-03).

## In progress
- Checkpoint ref.as_non_null, then install `/tmp/linear-array-new-default-family.lg` in census order.
- Exact next command (2026-10-03): `git push origin linear-target-m1 && gh pr checks 1`
- Array allocation preflight passed GC-disabled validation and wazero length/zeroing/type/growth probes (2026-10-03).
- Remaining family drafts: `/tmp/linear-*-family.lg`; structural Go probe: `/tmp/linear-m1-go-probe/values.go`.
- Current pinned first refusal: array.new_data in corpus/refused/linear/null.lg.

## Open questions
- Original runtime cache omits variadic dispatch state on restore; reported in the PR, the team is investigating. Keep GC output unchanged.
- Runner, linear oracle corpora, host-buffer twins, README paragraph and final GC gates remain pending.
