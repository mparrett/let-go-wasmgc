# LLVM Unicode case implementation

1. Extend existing string and values test groups; observe the current Unicode failure.
2. Generate deterministic compact range data from pinned let-go, with per-range reconstruction validation and source provenance.
3. Replace only the unsupported Unicode fallback in llvm.str with binary range lookup. Preserve ASCII/Latin-1 behavior and UTF-8 replacement semantics.
4. Run the string runtime group, consolidated values differential, three actual jank case files, and gensym/snapshot checks. Validate cache restoration after source changes.
5. Record exact outcomes and remaining blockers in docs and chit. Keep full-suite goal active until a complete census proves it.

## Verification so far

- Original string group exposed 12 Unicode failures before the implementation.
- Native string group passes 20 tests / 6,084 assertions, including a `check`
  property comparing upper/lower conversion of 300 generated strings to native
  let-go (seed 20261016). Generation mixes arbitrary Unicode scalars and known
  case-sensitive scripts; failures retain the seed and shrunk counterexample.
- Consolidated values fixture matches native output under ORC with reference checks.
- Generator `--check` passes: 199 upper / 183 lower ranges, covering 1,447 /
  1,432 changed scalars above Latin-1. Snapshot/gensym guard passes at 1,133.
- Review found no lookup/encoding defect. The provenance finding is addressed by
  checking the oracle executable's Go build version (go1.27.1) as well as its
  let-go commit, and recording both in the generated block.
- Actual jank upper_case/lower_case/capitalize pass 3/3 deftests and 33 assertions
  with no skips. Two values runs with runtime caching and ORC reference checks
  both MATCH, verifying creation/restoration. The full-suite census uses an earlier frozen source snapshot;
  its result cannot establish coverage for this change.
