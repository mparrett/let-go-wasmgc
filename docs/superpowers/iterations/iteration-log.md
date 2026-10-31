# LLVM reuse iteration evidence — 2026-10-15

Runtime snapshot key checks: renderer and cache module perturbations invalidate
the real key. Eight fast checks pass, including real file publication and mocked
build payloads across LLVM/GC/linear A/B/A. Real full-snapshot A/B/A passed: all native outputs match, B creates a distinct
entry, and A files retain their original modification times on the final restore.

Analysis cache tests: 5 tests, 19 assertions pass. Actual driver input/eligibility
checks: 3 tests, 11 assertions pass. Multi-arity mutable-template test was observed
failing before the exclusion was added. Separate compilation caches and failed
analysis retry are covered.

Self-host dependency packaging: real renamed driver loads from only packaged
sources and a pinned snapshot. Passed after adding both independent cache modules.

Runtime suite: 153 tests / 38130 assertions, zero failures/errors. Wrapper exit 1
because it captured 151 declared tests before two new cache tests were added.
Current declared count verified as 153. This is assertion evidence, not a clean
wrapper run; the five new unit tests passed separately with a fixed test count.

Initial executable fixtures: boxing analyses 14 -> 10, closure/exception analyses
14 -> 13, both 2 convergence rounds and identical native outputs. Script was
edited during execution and subsequently hit a shell parse-position error.
Final fixed harness rerun passed: boxing 14 -> 10, forward references 10 -> 8,
closures/exceptions/multi-arity 14 -> 13; all 2 rounds, all native outputs match.
Gensym guard 1133, runtime source snapshot round-trip, zero funnel violations
and self-host dependency load all passed in the same final run.

Performance passed: five-run Hyperfine means, baseline/disabled/enabled:
multi-round 3.569/3.752/2.938 s (17.7% faster than baseline); single-round
1.039/1.017/1.036 s (within noise). Multi-round105 executed/101 reused,2 rounds.
Raw measurements tracked under docs/benchmarks/llvm-reuse-2026-10-15/.
Benchmark setup fixes: explicit bash for Hyperfine2; numeric < comparison
instead of baseline-unsupported loop equality. No product workaround added.

## ITER-0002 — 2026-10-16

Native var lookup avoids repeated ns-interns map construction. Observed RED
100 map materializations; GREEN0. Four lookup tests pass with2524 assertions
on GC runtime and2526 on LLVM runtime. Compiler boxing/forward/templates native
behavior, gensym1133, snapshot round-trip, zero funnel violations and self-host
package load passed. Final ten-run timing649.3±12.2ms->387.0±9.4ms; peak
RSS137.6->117.7MiB. No persistent startup cache introduced.

Whole-module dylib prototype loaded with dlopen/dlsym and returned native fib35
output9227465. Dependency manifests and cross-unit ABI/state ownership remain
required before durable independent native artifacts.
