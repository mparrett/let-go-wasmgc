# LLVM reuse roadmap

## ITER-0000 — Correct and retain runtime cache entries

Stories: STORY-0001, STORY-0002.
Status: complete; real profile A/B/A verified.
Journey: JOURNEY-0001, real profile A → B → A.
Retain LLVM generations without changing GC/linear pruning. Key the IR renderer
and cache implementation alongside the existing compiler sources.

## ITER-0001 — Reuse analysis during signature convergence

Stories: STORY-0003, STORY-0004, STORY-0005.
Status: complete; final behavior gates and timing verified. Runtime suite
assertions passed with the test-count wrapper caveat in iteration-log.md.
Journey: JOURNEY-0002, boxing convergence with unchanged definitions and changed
callee interfaces; compare native, disabled reuse and enabled reuse.
Explicit definition input records; no persisted IR or lowered-text replay.

## Follow-on scope

Package lowering outputs with their globals, regions, runtime requirements and
ABI notes before persistent application caching. Enforce immutable analysis
inputs before expanding cache lifetime across compilations. These are not
claimed delivered by either iteration above.

## ITER-0002 — Reduce single-round compiler startup

Status: complete; final ten-run timing649.3->387.0ms and focused behavior
checks passed.
Proof: ten-run before/after single-round compilation; exhaustive runtime-var
identity checks in both targets; boxing/forward/closure execution; gensym and
self-host packaging sentinels.
Implementation: direct local var lookup instead of copying an entire namespace
map per lookup. Preserve map behavior for detached Namespace objects and unusual
keys, and preserve missing namespace failure. No additional caching state.

Follow-on exploration: native object cache with dependency/ABI manifests, loaded
through shared libraries or LLVM ORC. Whole-module dylib proof succeeds; durable
per-definition native artifact cache is not implemented in this iteration.

## ITER-0003 — ORC execution with durable native objects

Status: complete; extended parity/cache checks passed. Ten-run full source-to-run
ORC warm cache 617.7ms versus AOT 851.6ms; prepared-bitcode ORC warm
49.8ms (noisy), uncached 73.7ms. See docs/LLVM-CACHING.md and raw results.
Use isolated LLJIT process and a persistent whole-module relocatable object
cache. Preserve argv, host environment, return codes, initializers and libc
resolution; verify target/layout and input IR. Key by bitcode content, runner/
LLVM identity, target CPU/features/layout and optimization/codegen settings.
Atomic publication with integrity checks; helper modules must bypass the user
module cache. Keep explicit lli fallback and existing bare-board path.
Proof: AOT/lli/ORC parity, separate-process hit, invalidation, corruption,
concurrent writes, constructors/destructors, fresh environment/args, and real
compiler output from separate temporary directories. No claim of per-definition
reuse or avoiding the existing lg compiler startup yet.
