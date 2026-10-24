# Imported assertion routing

Run 89590 matches pinned let-go under ORC, without the runtime cache: 3 tests, 11 assertions, 3 intentional failures and 1 intentional error. Native and backend normalized summaries are preserved here. The consolidated wrapped-test fixture includes imported is/are/testing, an imported callable deftest, and a namespace inside top-level do. This is correctness evidence under concurrent load, not a performance benchmark.

The original imported-helper regression failed on test/fail-position reading test/*assertion-position* (run 2520). Scoped assertion macros now target the main file's shim counters. clojure.test is explicitly required before replacing its macro roots: otherwise a library's first require reloads the native macros. Roots are restored on both normal return and exceptions. The namespace owner scan splices top-level do, and the native runner and shell classifier recognize that form as a test file.

Reader lifecycle and namespace checks plus gensym/snapshot checks pass (run 98572; owner-specific run 25807), counter 1133. Renamed self-host source packaging loads (run 43079). Independent review identified the namespace-owner issue, which was reproduced (77388) and fixed. This does not establish a new whole-suite score; the frozen census currently running predates this change.

Actual jank not_eq (run 96634) advances past native test reporting but still scores 0/1: its next compile blocker is core/sorted-map-by with seven arguments. Diagnostic bar 0 returning exit 0 is not a passing test.
