# Clojure-defined BigInt and Ratio — proposed design

User direction: implement bignums and rationals in pure Clojure using deftype. This supports the LLVM/ORC jank goal and eventual integration into let-go. The direction is selected; representation details below are proposed, not yet validated.

## Representation and alternatives

Recommend immutable `(deftype BigInt [sign limbs])` and `(deftype Ratio [numerator denominator])`. Start with a portable persistent vector of bounded, nonnegative limbs. Choose limb width by proving that multiply/add/carry intermediates fit the pinned machine integer semantics, then benchmark. Do not assume 32-bit limb products fit signed 64-bit arithmetic. A 30-bit candidate leaves room for a single product plus bounded carry; document bounds for each algorithm.

A primitive array backing may reduce allocation but requires ownership rules and equivalent support across engines. Keep it as a measured optimization. Decimal-string arithmetic is simple for parsing but unsuitable as the general compute representation. Host Go big.Int or GMP arithmetic is not the intended implementation.

BigInt invariants: normalized sign, no high zero limbs, unique zero. Ratio invariants: nonzero positive denominator, coprime numerator/denominator, zero canonicalization. Match the pinned engine's exact rules for returning an integer when the denominator is one and for downgrading a BigInt that fits a machine integer; do not infer these rules from Clojure/JVM behavior.

## Prerequisite: compiled types

Provide genuine compiled deftype identity and fields, constructor and method invocation, and integration with type/instance?. Preserve LLVM's existing built-in TypeVal ancestry. The current shared driver's keyword/map stand-ins are insufficient for final numeric types: ordinary maps must not masquerade as numbers, and representation fields must not accidentally inherit map equality or printing. Upstream PR43 enables program type definitions but its progtypes fixture still fails LLVM instance? checks. Resolve this boundary before routing numeric values through user types.

Current implementation constraints checked in the tree:

- `src/lower_llvm_poly.lg` builds a closed table of native and abstract type IDs; `llvm.core` allocates its type cache to that static count. User types need an explicit registration/allocation strategy rather than indexing beyond this array.
- `llvm.core/TypeVal` already carries name, identity, ancestry, method table and epoch. Reuse that contract for user-defined types and preserve built-in dispatch.
- `llvm.core/ckind` and `dispatch-id` distinguish runtime layouts from language types. A user-instance representation must participate in both paths and in GC field tracing.
- Float32 and Float64 are distinct in the pinned engine (`double? (float 1.0)` is false). The LLVM runtime currently boxes both through its Float representation. Numeric integration must preserve this distinction; aliasing double? to the existing float predicate would be wrong.

## Arithmetic and integration

Build a small unsigned limb kernel: normalize, compare, add/subtract, multiply, shifts, quotient/remainder, and gcd. Layer signed BigInt operations and decimal parsing/printing over it, then Ratio arithmetic and reduction. Start with simple proven algorithms; specialize multiplication/division only when benchmarks justify it.

Reader-produced native BigInt/Ratio constants must become compiled constructors without losing precision. Reader objects may remain the compiler input representation; emitted arithmetic and values use the Clojure-defined types. Include constants in collections, quoted forms, eval, snapshots and durable cache serialization.

Integrate exact and mixed arithmetic, checked versus promoting operators, comparisons, predicates, abs, quotient/remainder/modulo, conversions, equality and hashing. Equal numeric map keys must hash compatibly with existing machine-number keys where the pinned oracle requires it. Keep ordinary machine-integer and floating-point operations on their existing fast paths.

BigDecimal is a separate outstanding requirement. Supporting BigInt and Ratio alone does not satisfy the full jank suite.

## Sequence and evidence

1. Type representation and minimal protocol/method behavior: differential fixtures for identity, fields, constructors and instance?; retain existing built-in ancestry tests.
2. Limb kernel and BigInt: boundary vectors, deterministic randomized oracle comparisons, carry/borrow chains, signs, zero, large quotients and products.
3. Ratio: normalization, denominator sign, divide-by-zero, cancellation and exact comparison; validate return-type behavior against pinned let-go.
4. Compiler/runtime integration: literal round trips, dynamic calls, cross-type equality/hash, map/set keys, printing and cache round trips.
5. Run the complete jank suite, classify every remaining discrepancy, and resolve it without skips or lowering the pass criterion.
6. Measure warm ORC arithmetic and allocation alongside bytecode and native Go. Include small integers to detect regressions and large values to measure the new implementation. Report cold compilation separately from warm execution.

Use pinned lg e9789b7d53 as behavioral oracle. Native Go big.Int/big.Rat can supply independent test expectations and performance baselines, but are not linked as the production arithmetic implementation.
