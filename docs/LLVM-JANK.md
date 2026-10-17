# LLVM ORC jank compatibility

The objective is full jank-suite compatibility on LLVM ORC, with measured cold
compilation and warm execution performance. Use pinned let-go `e9789b7d53`
as the oracle; the sibling working tree has unrelated changes.

## Current full-suite result

The completed 2026-10-17 frozen census passes **154/242 deftests (63.6%)**:
154/241 files MATCH, all definitions attempted, no skips. `reduce` improved
from the previous full census; no files regressed.

[Canonical census evidence](benchmarks/jank-latest.json) contains the per-file
results, command, and frozen source hashes. Reuse this file for the next full
census rather than creating a directory per run. This snapshot includes the
namespace, mutable-field, descriptor-method, array, numeric-equality and
collection-reduce fixes. It excludes the subsequent pure Clojure numeric
library and operator integration work.

The harness used `--bar 0` for diagnosis. A successful harness exit means the
census completed, not that compatibility passed. Remaining failure labels are
heuristic: one labelled numeric failure and 86 mismatching
files containing 87 deftests. Numeric omissions affect more than the labelled
numeric failure. This was not an isolated performance measurement.

## Current work and remaining requirements

- LLVM deftypes have real identity, field access, metadata, printing, hashing,
  and mutable field storage. Lexical method rewriting handles live reads,
  delayed closures, ordinary macro expansion, and foreign namespaces. Both
  runtime cache creation and restoration pass the consolidated definitions
  fixture. Small-heap mutation checks and generated properties also pass.
- Descriptor-owned protocol methods preserve existing instances across type
  redefinition. The expanded differential and generated isolation properties
  pass. Builtin method-table GC roots and compiler-side extension updates
  pass the definitions fixture with a 1 MiB heap. Type-alias invalidation and
  explicit nil/false root stores pass the expanded definitions fixture.
  Nil-target extensions, macro-side nil aliases, and source-order macro
  expansion also pass the small-heap fixture. Broader extension forms, inheritance,
  interfaces, and redefinition behavior remain under development. Follow the
  [existing user-type plan](superpowers/plans/2026-10-17-llvm-user-types.md).
- Integer constructor aliases are registered with the integer conversion twin.
  The subsequent `reduce.cljc` error was a stubbed test body caused by missing
  `into-array`, not nil-function exception behavior. Program stub diagnostics
  now preserve the full error rather than truncating the missing symbol.
  `into-array` and unboxed floating array storage pass the existing values
  differential and seeded collection property. Arbitrary-arity numeric equality
  and collection `.reduce` delegation now pass the calls fixture. The actual
  `reduce.cljc` matches native on ORC with all ten assertions and no skips,
  using the restored runtime cache. This focused result does not replace the
  full census above. It also exposed and fixed a cache-key omission: LLVM's
  loaded extension source must be hashed, rather than the GC extension file.
- Records still use tagged maps and have unresolved type semantics.
- Implement the [pure Clojure numeric tower](superpowers/specs/2026-10-16-clojure-numeric-tower-design.md):
  BigInt and Ratio through deftype, including operations, literals, equality,
  hashing, printing, and serialization. BigDecimal and distinct Float32
  behavior remain required. The unsigned pure Clojure limb kernel now has
  normalization, comparison, arithmetic, shifts, division/remainder and gcd.
  It passes native arbitrary-precision properties in the existing core group
  and ORC/bytecode boundary comparisons. Pure Clojure BigInt and Ratio deftypes
  now provide signed and rational arithmetic with native normalization and
  integral-result type rules. Native properties caught and verified a fix for
  negating a simplified MinInt64. Operator dispatch, literals, equality/hash,
  printing and compiler/runtime integration remain unfinished; these library
  checks do not change the full-suite score.
- Complete multimethods, remaining Var/namespace semantics, and the other
  discrepancies identified by the full census. The earlier evaluator
  `core-table*` bit-function blocker is resolved; the actual eval test passes.
- Measure cold compilation, runtime-cache restoration, and warm execution
  after correctness changes. Existing measurements and cache limitations are
  in [LLVM-CACHING.md](LLVM-CACHING.md). No new performance claim follows from
  the compatibility checks.

## Regression discipline

Keep differential cases in `checks/fixtures/jank-reader/{values,calls,atoms,definitions}.lg`
and properties in the existing native runtime groups. The uncaught-error
fixture remains separate because it checks process exit behavior. Temporary
probes stay temporary; summarize useful failure and fix evidence in existing
documentation rather than adding source copies, split logs, and manifests for
every probe.

Imported helper assertions and callable library deftests must use the main
file's assertion shim. Require the embedded test namespace before replacing
its macro roots, then restore them even when compilation throws. The wrapped
fixture includes intentional failures and an error to verify shared reporting.

Preserve evaluated collection allocation and regex literal identity. Allocation
calls cannot be hoisted out of loops solely because their values compare equal.
ORC currently uses nonmoving mark/sweep; small-heap checks prove collection
survival, not relocation.

Use Chit ledger `llvm-orc-jank` for actionable handoffs and unresolved decisions.
The full suite and performance objective remain open; focused fixtures and
runtime properties cannot substitute for either whole-suite verification or
isolated timing measurements.
