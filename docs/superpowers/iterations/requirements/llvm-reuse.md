# LLVM reuse requirements

Source: the user's request to iterate on caching and reuse, after the
per-definition/interface discussion. The October 10 tracing plan is historical;
this run does not implement compiler-function wrappers.

- STORY-0001: LLVM runtime snapshots invalidate when the renderer changes.
  Proof: perturb the real source read in the key check; the key must differ.
- STORY-0002: switching profile A → B → A reuses A's snapshot and runs correctly.
  Proof: real native executables match pinned lg and A's snapshot is not rewritten.
- STORY-0003: reuse completed per-definition analysis within boxing convergence.
  Proof: enabled and disabled executables match native; enabled performs fewer
  analyses with the same number of rounds. Dependency discovery, signature
  publication and lowering still execute on every round.
- STORY-0004: changed definition interfaces invalidate analysis; mutable child
  templates and failed analyses are never reused. No cache leaks between compiles.
  Proof: boundary/unit checks and real closure/exception/multi-arity compilation.
- STORY-0005: measure overhead and benefit, preserving other targets.
  Proof: quiet hyperfine baseline/disabled/enabled runs; runtime tests and load
  gensym guard. Counts alone do not establish a speed improvement.

Scope: two bounded iterations. Persistent application-definition artifacts,
runtime per-function rebuilds and pure lowering over explicit context remain
follow-on work. This cache is compilation-local, so pass identity, runtime
definitions and source-resolution context are fixed throughout its lifetime.
