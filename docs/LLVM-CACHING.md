# LLVM caching and reuse

The LLVM backend has a persistent runtime snapshot and a compilation-local
definition analysis cache. Application LLVM units are still lowered on every
invocation; this is not yet a persistent application-function cache.

## Runtime snapshots

`LW_RTLIB_DIR` selects the snapshot directory (default `src/.rtlib`). The key
includes runtime sources, the pinned lg binary, compiler sources including the
LLVM IR renderer, configuration, and the hardware profile. Rooted-native
variants remain separate.

The extension input is the file actually loaded (`lw-rt/ext-path`): LLVM uses
`rt/llvm/ext.lg`, including `LW_RT_DIR` overrides. Hashing the GC extension file
instead previously let LLVM restore stale method implementations. The cache
lifecycle check covers this input; serialized driver snapshots embed its forms.

LLVM retains previous keys, so switching from one hardware profile or compiler
generation to another and back can reuse the original snapshot. These files
are disposable, but are no longer automatically evicted. Long-lived directories
can grow; use a task-specific `LW_RTLIB_DIR` when you want to discard a run's
snapshots afterward. GC and linear targets keep their existing eviction policy.

## Definition analysis

When the driver discovers that more function parameters need boxing, it runs
another convergence round. Unchanged LLVM definitions can reuse completed
analysis from an earlier round of that same compilation.

The input record includes the source and its metadata, namespace, emitted name,
multi-arity and boxing settings, and the whole interface of each referenced
definition (including mapped runtime implementations). Changed inputs cause a
fresh analysis. Dependency discovery and signature publication still run, and
lowering always runs to produce its module-state effects and ABI observations.

Functions containing closure or exception templates bypass reuse: lowering
optimizes their child IR in place. Failures are not cached. Each compilation
creates a fresh cache, and non-LLVM targets do not use it.

This boundary relies on compiler passes, runtime definitions and namespace
bindings remaining fixed during convergence. Analysis still reads the existing
compiler state; the input record is not an enforced isolated context. Persistent
reuse requires that stronger boundary and explicit ownership of lowering's
globals, regions, runtime requirements and ABI notes.

- `LW_LL_ANALYSIS_REUSE=0` disables analysis reuse for differential checks.
- `LW_LL_ANALYSIS_STATS=1` prints executed/reused/bypassed counts and convergence
  rounds on stderr. These count driver definition analyses, not every internal
  IR pass or runtime-library function.

## Checks

Run build checks through the shared CPU baton on a coordinated development
machine. Timing checks take their own exclusive lease; never nest that inside a
shared build lease.

```sh
bash checks/llvm-rtlib-reuse-check.sh
LLVM_RTLIB_REUSE_FULL=1 bash checks/llvm-rtlib-reuse-check.sh
bash checks/llvm-analysis-reuse-check.sh
bash checks/self-compile-deps-check.sh
checks/quiet.sh caffeinate -i bash checks/bench-llvm-analysis-reuse.sh
```

The profile check compiles and runs A → B → A, compares all outputs with native
lg, and verifies that A's snapshot is not rewritten. The analysis check compares
native execution and compiled execution with reuse on/off, exercises boxing,
forward calls, closures and exceptions, and requires fewer analyses with the
same convergence rounds. The benchmark compares the committed driver with
working-tree reuse disabled/enabled on synthetic multi-round and single-round
workloads. It measures compiler time, not executable performance.

## Measured result — 2026-10-15

Pinned lg `e9789b7d53`, baseline driver from `13a0c03`, Darwin arm64;
Hyperfine 2.0.0, one warmup and five measured runs per case, under the exclusive
CPU baton. Means and sample standard deviations:

| Workload | Baseline | Reuse disabled | Reuse enabled |
| --- | --- | --- | --- |
| 100 independent loop functions, two boxing rounds | 3.569 ± 0.056 s | 3.752 ± 0.195 s | 2.938 ± 0.065 s |
| Single-round Fibonacci | 1.039 ± 0.044 s | 1.017 ± 0.008 s | 1.036 ± 0.030 s |

The synthetic multi-round case executes 105 analyses and reuses 101, reducing
compile time by 17.7% against the baseline. Peak memory is essentially unchanged
(154.7 versus 155.1 MiB). The single-round difference is within observed noise.
These measurements do not establish a speedup for large applications or their
runtime execution. Raw measurements are in `benchmarks/llvm-reuse-2026-10-15/`.

The real runtime profile A/B/A check and all three executable analysis fixtures
passed. The runtime suite executed 153 tests / 38,130 assertions with zero test
failures or errors; its wrapper exited unsuccessfully because it counted 151
tests before two tests were added during the run. The final cache unit tests
passed separately with a fixed count, as did the final behavior harness, gensym
guard, state-access check and self-host packaging check.

## Startup lookup improvement — 2026-10-16

Profiling found that `lw-rt/ns-var` built an entire namespace map for each lookup.
The native path now directly looks up a local var, including private vars and
excluding refers. Namespace objects and unusual keys retain the original map
semantics. Missing namespaces still fail; newly interned or replaced vars are
visible immediately. This removes repeated allocation without adding cache state.

The final ten-run comparison measured 649.3 ± 12.2 ms before and 387.0 ± 9.4 ms
after (40.4% reduction), with peak memory falling from 137.6 to 117.7 MiB.
Raw results are in `benchmarks/llvm-startup-2026-10-16/final.json`.
Yesterday's approximately one-second baseline was taken under heavier load;
compare the same-day before/after measurements for the code change's effect.

Reproduce with `checks/quiet.sh caffeinate -i bash checks/bench-llvm-startup.sh`.
This compares the committed `lw_rt.lg` with the working tree while holding the
rest of the compiler fixed. The lookup regression check verifies every indexed
runtime var against its native namespace table in both targets, plus mutation,
private vars, aliases, missing names, and detached Namespace objects.

Bytecode replay was explored but hit existing source-path and namespace-alias
problems. The existing source snapshot reduced memory but was slower in this
workload (716 versus 667 ms). Neither exploratory approach is enabled.

## Native artifact direction

A local proof built the emitted Fibonacci LLVM module and C host into a macOS
`.dylib`, loaded it with `dlopen`, resolved its C `main` entry, and produced the
expected 9227465. This demonstrates whole-module native loading, not a finished
persistent cache or safe in-process integration with let-go's VM.

The proposed reusable unit is compiled object code plus a manifest: exported and
required symbols, source/pass/dependency identities, target profile, and runtime
ABI/layout identity. Objects can be linked into executables or shared libraries;
LLVM ORC can also load relocatable objects directly. Lookup metadata must remain
separate from process-specific addresses. Grouping units into shared libraries
is a packaging choice once their dependencies and state ownership are explicit.

The current emitter's `tailcc` functions require their matching calling
convention; a C entry wrapper is needed at a native embedding boundary. Type IDs,
GC roots, globals and initialization must also have an explicit cross-unit
contract before independently compiled definitions can safely share a runtime.
See [LLVM ORC](https://llvm.org/docs/ORCv2.html) and
[JITLink](https://llvm.org/docs/JITLink.html) for object-loading support.

## Bytecode comparison — 2026-10-16

Same pinned binary and Fibonacci definition, three warmups and twenty fresh
processes per command under the exclusive CPU baton:

| Phase | Bytecode engine | LLVM path |
| --- | ---: | ---: |
| Compiler startup | 7.3 ± 0.6 ms | 299.8 ± 14.3 ms |
| Startup + compile to engine representation | 8.0 ± 0.7 ms (`.lgb`) | 377.0 ± 16.6 ms (`.ll`) |
| LLVM machine-code generation + native link | — | 263.8 ± 6.7 ms |

The final recursive invocation is removed from both inputs: pinned `lg -c`
executes top-level forms during compilation, which would otherwise measure
fib(35) execution too. The final native link includes compiling the current C
host files. Filesystem caches are warm; these are process startup measurements,
not cold-disk measurements. Subtracting the first row from the second gives
only a rough estimate of incremental compilation, not an in-process timer.
Reproduce with `checks/quiet.sh caffeinate -i bash checks/bench-llvm-bytecode.sh`.
Raw measurements: `benchmarks/llvm-bytecode-2026-10-16/results.json`.

## ORC object cache — 2026-10-16

`LW_NATIVE_JIT=orc` (also `1`) now uses an isolated LLVM LLJIT executor with a
persistent relocatable-object cache. The AOT default is unchanged;
`LW_NATIVE_JIT=lli` selects the previous executor. Tested on Darwin arm64 with
LLVM 23.1.2. Set `LLVM_BIN` to select the LLVM tools directory.

```sh
# Prepare once; exporting the runner avoids hashing the toolchain on every run.
export LW_ORC_RUNNER=$(bash checks/build-orc-runner.sh)
LW_NATIVE_JIT=orc LW_ORC_STATS=1 bash checks/native-run.sh corpus/scalar/fib.clj
```

The builder keys the runner by source, build flags, LLVM libraries and compiler
binary. Objects default to `src/.orc/`; override with `LW_ORC_CACHE_DIR`.
`LW_ORC_CACHE=0` disables object reuse, `LW_ORC_OPT_LEVEL=0|1|2|3` selects
optimization (default 2), and `LW_ORC_STATS=1` prints cache counters to stderr.
Old generations are retained; there is currently no automatic size limit.
The cache directory is trusted local executable storage.

Each object key includes exact linked input bytes, runner/toolchain identity,
host triple, CPU/features, data layout and optimization/code-generation settings.
Objects contain a payload checksum and are published by atomic rename. Truncated
or corrupt entries are recompiled; unavailable cache storage degrades to uncached
execution. Runtime arguments, environment and file reads remain fresh each run.
No process addresses are persisted. Initializers and destructors run per process.

This is whole-module reuse, including the linked C host. It skips machine-code
generation on a hit, but still parses, validates and optimizes IR. Applying the
same optimization on cold and warm paths is necessary for ORC's advertised
symbols to match the cached object when optimization discards definitions.
Frontend lowering, host C bitcode compilation and bitcode linking still run.
Per-definition artifacts, dependency manifests, embedding into let-go's process,
and durable frontend outputs remain future work.

Ten measured runs with two warmups under the exclusive CPU baton, using the
same Fibonacci definitions with the recursive invocation removed:

| Path | Mean ± standard deviation |
| --- | ---: |
| Prepared bitcode, lli | 48.1 ± 1.5 ms |
| Prepared bitcode, ORC cache disabled | 73.7 ± 3.2 ms |
| Prepared bitcode, ORC warm cache | 49.8 ± 27.4 ms |
| Source → AOT execution | 851.6 ± 27.6 ms |
| Source → lli execution | 624.7 ± 14.5 ms |
| Source → ORC warm-cache execution | 617.7 ± 15.5 ms |

The warm executor sample includes a 127.8 ms outlier (minimum 39.7 ms); these
measurements do not establish a meaningful advantage over lli. Full ORC source
to execution is 27.5% faster than AOT here. Runner construction and toolchain
identity hashing are excluded by preparing `LW_ORC_RUNNER` once. The full command
includes compiler startup and rebuilding the host bitcode. These numbers measure
compilation and execution setup, not recursive Fibonacci throughput.

Reproduce with `checks/quiet.sh caffeinate -i bash checks/bench-orc.sh`.
Raw results: `benchmarks/llvm-orc-2026-10-16/`.

`LLVM_ORC_EXTENDED=1 bash checks/llvm-orc-check.sh` passed: native/AOT/lli parity,
process inputs and exit codes, constructors/destructors, text IR, relocated cache
hits, source/config invalidation and return-to-config reuse, disabled caching,
corruption recovery, concurrent writers, discarded-symbol warm hits, invalid
main ABI/IR/target rejection, and real compiler output. Extended native/AOT/ORC
cold/warm checks passed for closures, exceptions, fixnum edges and GC churn.

## Warm compute — 2026-10-16

Three measured processes per engine under the exclusive CPU baton. Each program
warms ten calls, then times 1,000 calls internally with `System/nanoTime`; reading,
compiling, loading, object relocation and initialization precede the timer.
Fibonacci alternates tree-recursive fib(20) and fib(21). XXH3 hashes a prebuilt
1,024-byte buffer, changing the seed from 0 through 999. Checksums are consumed
and printed, and agree across all engines: 8855500 and -8755576988160712384.
The XXH3 checksum also agrees with pinned let-go's native Go xxh3 binding.

| 1,000 calls, warm compute only | Pinned bytecode | LLVM AOT | LLVM ORC |
| --- | ---: | ---: | ---: |
| fib(20/21) | 1852 ± 59 ms | 627 ± 73 ms | 555 ± 20 ms |
| XXH3, 1 KiB, varying seeds | 3787 ± 51 ms | 47.4 ± 8.0 ms | 38.8 ± 1.2 ms |

Values are means ± sample standard deviations. ORC is approximately 3.3x faster
than bytecode on Fibonacci and 98x on this XXH3 comparison. AOT measurements
trend downward across these three samples, so the small sample does not establish
a reliable ORC-versus-AOT compute advantage.

The XXH3 comparison uses `llvm.xxhash/hash-bytes`, the same Clojure-style algorithm
on both engines. On bytecode, `llvm.arch` emulates low-level memory and arithmetic
with checked reference operations; LLVM lowers them to intrinsics. This is not
98x faster than the native Go xxhash binding, nor evidence for that speedup on
arbitrary Clojure programs. The workload includes per-hash allocations and secret
initialization for varying nonzero seeds; buffer construction is outside timing.

Every measured ORC process reported `hits=1 misses=0 writes=0 invalid=0`.
Despite cache hits, mean full process durations were 1.080 s for Fibonacci and
0.569 s for XXH3, versus compute-only 0.555 s and 0.039 s. These modules include
runtime clock/printing support; parse/optimization/link/initialization costs are
larger than in the earlier definition-only startup benchmark. Object reuse does
not make each new process an already-running VM.

Reproduce with:

```sh
checks/quiet.sh caffeinate -i bash checks/bench-llvm-compute.sh
```

The script prepares LLVM IR, bitcode, AOT executables and the ORC runner before
sampling, verifies matching checksums and cache hits, and writes `results.json`
to `/tmp/llvm-compute-bench` (or its first argument). Raw measurements are in
`benchmarks/llvm-compute-2026-10-16/results.json`; source fixtures are in
`checks/fixtures/compute/`. No optimization flags beyond the existing O2 pipeline
or compiler implementation were changed for this benchmark.

### Native Go XXH3 comparison

Follow-up: seven samples per implementation, rotating execution order under the
exclusive CPU baton. Same 1 KiB input, seeds 0–999, ten in-process warmup calls,
1,000 timed hashes, prewarmed executables, matching checksum
`-8755576988160712384`. Startup and compilation are outside the internal timer.
Go is 1.27.1 (matching the pinned lg binary), `github.com/zeebo/xxh3 v1.1.0`.

| Implementation | Mean ± standard deviation for 1,000 hashes |
| --- | ---: |
| Direct Go HashSeed calls | 0.049 ± 0.014 ms |
| Go HashSeed through pinned let-go binding | 0.320 ± 0.012 ms |
| Clojure-style runtime port, LLVM AOT | 38.40 ± 2.03 ms |
| Clojure-style runtime port, LLVM ORC | 50.99 ± 5.22 ms |

Native Go is about 1,040x faster than ORC in this sample; even through the VM
binding it is about 160x faster. The earlier 98x improvement over the interpreted
reference implementation must not be mistaken for competitive native hashing.
The Go package's arm64 path uses its NEON assembly accumulator; the runtime port
implements scalar arithmetic, byte assembly and runtime allocations. This is an
algorithm/representation/implementation comparison, not a general Go-versus-LLVM
compiler comparison. Profiling is needed to apportion the performance gap.

The ORC follow-up is slower than the earlier 38.8ms sample; raw samples preserve
that variability rather than reusing the earlier number. Every measured ORC run
reported an object-cache hit. Direct-Go durations are very short; the seven-run
variation is reported rather than implying precision from the nanosecond timer.

Reproduce after preparing the earlier benchmark artifacts:

```sh
checks/quiet.sh caffeinate -i bash checks/bench-xxh-go.sh
```

Sources: `checks/fixtures/compute/xxh-go.lg` and
`checks/fixtures/compute/go-xxh/main.go`. The script builds an isolated Go module
in the output directory, leaving the let-go checkout unchanged. Raw results:
`benchmarks/llvm-compute-2026-10-16/go-comparison.json`.
