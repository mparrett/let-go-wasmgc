# Progress — 2026-10-03

## Done
- Read README.md, docs/READING-GUIDE.md and docs/LINEAR-TARGET-SPEC.md in order.
- Branch `linear-target-m1`; draft PR https://github.com/mparrett/let-go-wasmgc/pull/1 .
- Target/cache, frozen GC guard, shared representation, numeric module and leaking allocator are pushed (2026-10-03).
- Census families through call_ref are pushed as `6e8be45`; default/explicit GC byte checks and publish CI passed (2026-10-03).
- D172-D177 record nominal headers, representation placement, cache variance, safe host-buffer ownership and the existing P1.1 division exclusions (2026-10-03).

## In progress
- Next census family: array.new_data; update target checks to use a supported nil fixture and pin array.fill as a compile refusal (2026-10-03).
- Exact next command (2026-10-03): `/tmp/linear-m1-next-arrays.sh`
- Sequential checkpoint command: `/tmp/linear-m1-next-arrays.sh`; stop on any failure (2026-10-03).
- Remaining census drafts, imported function signatures, cast branches and host-buffer retries passed GC-disabled preflight (2026-10-03).
- Complete temporary draft with the full runtime produced native-oracle MATCH for corpus/scalar/fib.clj (2026-10-03); committed corpus acceptance remains pending.
- Remaining family drafts: `/tmp/linear-*-family.lg`; temporary runner draft: `/tmp/linear-m1-runner-draft/` (2026-10-03).
- Current pinned first refusal: array.new_data in corpus/refused/linear/null.lg.

## Open questions
- Original runtime cache omits variadic dispatch state on restore; reported in the PR, the team is investigating. Keep GC output unchanged.
- Runner, linear oracle corpora, host-buffer twins, README paragraph and final GC gates remain pending.
