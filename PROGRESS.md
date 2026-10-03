# Progress — 2026-10-03

## Done
- Read README.md, docs/READING-GUIDE.md and docs/LINEAR-TARGET-SPEC.md in order.
- Target selection, isolated caches and frozen GC byte guard are pushed as `06e9eed` (2026-10-03).
- Shared representation boundary is pushed as `36f9463`; publish CI passed (2026-10-03).
- Linear module/type skeleton and leaking allocator are validated; target check and default/explicit GC identity over all scalar/eval programs passed (2026-10-03).
- Allocator prototype passed memory growth under the specified wazero fork; structural evidence, no oracle MATCH claim (2026-10-03).
- Draft PR: https://github.com/mparrett/let-go-wasmgc/pull/1 .
- D172-D175 record layout, representation and cache-state decisions (2026-10-03).

## In progress
- Checkpoint the type/allocator foundation, then implement instruction families in census order.
- Cast-family draft is preserved in `/tmp/linear-cast-family.lg`.
- Exact next command: `git push origin linear-target-m1 && gh pr checks 1`
- Then install the cast family, run its structural probe and target check, and rerun the GC byte guard before committing.

## Open questions
- Original runtime cache omits some variadic dispatch state when restored; reported in the PR without changing GC output. The team is investigating.
- All linear oracle corpora, runner and final gates remain pending.
