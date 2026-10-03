# Progress — 2026-10-03

## Done
- Read README.md, docs/READING-GUIDE.md and docs/LINEAR-TARGET-SPEC.md in order.
- Driver target selection and isolated caches are committed and pushed as `06e9eed` (2026-10-03).
- GC byte guard and target-selection row passed (2026-10-03).
- Draft PR is open: https://github.com/mparrett/let-go-wasmgc/pull/1 . Publish CI passed (2026-10-03).
- D172 records the nominal-header amendment; D173 records original cache-state byte variance (2026-10-03).

## In progress
- Route the shared instruction stream through the representation boundary. GC remains verbatim; linear still refuses `ref.null`.
- Linear parser/layout definitions are loaded only on demand; the full GC byte guard passed again (2026-10-03).
- Exact next command: `LW_ATTEST=0 checks/run.sh P8.1`
- Commit and push this green representation foundation.
- Then add linear instruction families in the spec's census order, followed by the runner and oracle corpora.

## Open questions
- Original runtime cache omits some variadic dispatch state when restored; reported in the PR without changing GC output.
