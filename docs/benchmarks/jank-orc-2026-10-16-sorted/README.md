# Custom sorted comparator evidence

The consolidated values fixture matches under ORC after implementing custom
sorted comparators and saturating numeric-result normalization (run 93386).
The native core group passes 16 tests / 14,165 assertions, including a `check`
property with 150 generated update/removal sequences, seed 20261017, retaining
all prior map/set versions against an independent model. Review found no new
implementation defect. The later callable-map case is pending in the small-heap
cache run, not covered by run 93386.

Actual jank eq/not_eq both compile and run all 71 assertions, but remain failing:
eq has two failures, zero errors; not_eq has two failures and two errors. Native
has no failures/errors. Thus these files are **0/2 passing**, not a compatibility
gain yet. The former missing-constructor compile blocker is gone.

The worker results.tsv was completed, but the outer shell reporting failed
because its script was edited while it was running. Do not treat the run's
exit status as a valid harness verdict. The worker counts and captured not_eq
transcript are diagnostic evidence only; the final tests require a clean run.

The diagnostic wrapper completed: all sorted comparisons passed. The two
failures in each group are NaN-containing set equality and distinct regex
literal equality. The extra not_eq errors are missing five-/seven-argument
variants of `not=`. See equality-diagnostics.log; its exit zero does not mean
the assertions passed (the test summary has four failures and two errors).

Small-heap GC/reference checks and cache creation/restoration matched twice,
including the final callable-map fixture case (run 63980, 1 MiB heap).
Source manifest covers runtime/fixture state; it does not claim the final
fixture additions were exercised by the earlier passing ORC run.
