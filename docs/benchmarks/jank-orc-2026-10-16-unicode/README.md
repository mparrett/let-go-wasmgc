# Unicode case compatibility, 2026-10-16

Actual jank `capitalize`, `lower_case`, and `upper_case`: **3/3 deftests,
33 assertions, no failures, errors, or skips**, matching pinned native let-go.
See results.tsv and run.log. Run with `LW_NATIVE_JIT=orc`,
`WASM_RUN=checks/native-run.sh`, `P=1`, and
`checks/jank-suite.sh --filter upper_case,lower_case,capitalize`.

The consolidated string runtime group separately passes 20 tests and 6,084
assertions. This includes a seeded `check` property for 300 generated Unicode
strings, with shrinking. It runs the LLVM runtime functions under native
let-go; the jank results above verify emitted ORC execution.

The generator verifies all Unicode scalars above Latin-1 against pinned let-go
e9789b7d53 built with go1.27.1, producing 199 uppercase and 183 lowercase
ranges. Both commit and toolchain are checked. The consolidated values fixture
also matches with `--no-rtlib` and ORC reference checks.

Source hashes are recorded in source-manifest.json. The full census running
concurrently uses an earlier frozen source tree and excludes these fixes.
These targeted results do not establish a new full-suite score. Shared-load
wall times, including full runtime cache prewarming, are not performance
benchmarks. The separate two-pass values check with the runtime cache enabled
and ORC reference checks produced MATCH twice (363.5 seconds under shared load,
including cache creation). This verifies cache creation/restoration for the
Unicode source generation before the subsequent sorted-comparator edits.
