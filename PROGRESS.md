# Progress — 2026-10-03

## Done
- Read README.md, docs/READING-GUIDE.md and docs/LINEAR-TARGET-SPEC.md in order.
- Created branch `linear-target-m1`; verified GitHub access.
- Added driver target parsing, session target and separate runtime/module cache keys.
- Target selection check passed; unfinished linear instructions are named compile errors.
- GC byte guard passed over all scalar and eval programs with default and explicit GC (2026-10-03).
- Captured pre-change GC binaries; diagnosed pre-existing cold/warm cache byte variance on the original compiler (D173, 2026-10-03).

## In progress
- Exact next command: `git push -u origin linear-target-m1`
- Commit and push the green WIP foundation, as requested.
- Representation layer and linear instruction families remain unimplemented.

## Open questions
- Original runtime cache omits some variadic dispatch state when restored; report this in the PR without changing GC output.
- Nominal casts need a type word alongside semantic kind and size (D172, 2026-10-03).
