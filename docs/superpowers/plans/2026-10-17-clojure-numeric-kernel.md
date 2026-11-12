# Pure Clojure numeric kernel implementation plan

> Execute sequentially under the existing numeric-tower direction. Keep tests
> in the existing generated numeric group; do not create per-operation suites.

**Goal:** Supply portable exact arithmetic for deftype BigInt and Ratio, then
integrate it into LLVM ORC without replacing the machine-number fast paths.

**Architecture:** `rt/numeric/limbs.lg` owns unsigned, little-endian vectors in
base 2^30. Empty vector is zero; nonzero values have no high zero limb. Signed
BigInt and normalized Ratio definitions will wrap this kernel. Production
arithmetic uses ordinary Clojure integer operations, never host bignum calls.

**Bounds:** Let B = 2^30. Addition intermediates are at most 2B-1. A schoolbook
multiply step is a*b + existing-limb + carry, at most (B-1)^2 + 2(B-1) = B^2-1,
which fits below 2^60. Carry is at most B-1. Subtraction stays in [-B, B-1].
These bounds fit the pinned engine's signed 64-bit machine integers.

Shifts split the count into whole limbs and a residual r < 30. Left shifts
multiply each limb by 2^r and carry immediately, keeping intermediates below
B*2^29. Right shifts combine the high remainder with the next limb; each
output remains below B. Negative counts are rejected by the unsigned kernel.

For a one-limb divisor, scan high to low with s = remainder*B + limb.
Since remainder < divisor < B, s < B^2 and each quotient limb is below B.
For larger divisors, align the divisor by bit length, subtract
when it fits, then shift it right one bit. After each position the remainder
is below the divisor at that position, so the next quotient digit is 0 or 1.
This uses only the bounded shift and subtract operations. Division by zero
must throw. Gcd uses Euclidean remainders; gcd(0,0) is zero. Native arbitrary
precision supplies independent quotient, remainder and gcd expectations in
the existing property group. More specialized division remains a measured
optimization, not a prerequisite for exact numeric integration.

## Kernel and evidence

- [x] Extend `corpus/llvm-rt/core_test.lg`'s existing numeric property group.
  Convert generated limb vectors to native BigInts in test code only. Compare
  normalize, compare, addition, nonnegative subtraction and multiplication,
  checking canonical output and unchanged input vectors.
- [x] Run the group and capture a missing-kernel failure before implementation.
- [x] Implement those operations in `rt/numeric/limbs.lg`. Use local transient
  output storage for schoolbook multiplication; return immutable normalized
  vectors. Reject subtraction underflow rather than wrapping.
- [x] Run the native group through `checks/intrinsics-native-runner.lg 16
  core-test` with source paths `rt:src:corpus/llvm-rt`.
- [x] Compile a temporary differential program through `checks/oracle.sh`,
  with `LG_ARGS=-source-paths rt`, to verify that ORC executes the same kernel.
  ORC matched bytecode for zero, carry, borrow, equal subtraction and multiply
  across 31/32/33-limb vectors. Native execution exited successfully, so the
  match is not two matching error reports. Keep permanent randomized regression
  coverage in the existing numeric group; do not add this to cache benchmarks.
- [x] Add shifts, quotient/remainder and gcd with generated algebraic and
  native-oracle checks, including exact division and boundary carries. The
  existing core group passes with no failures or errors; ORC matches bytecode
  for shifts, division and gcd in the temporary differential probe. Negative
  shift counts and division by zero are covered in the native group.

## Signed values and integration

`numeric.bigint/BigInt` uses sign -1/0/1 and normalized limbs. Its arithmetic
retains the BigInt representation for small results, matching pinned
`vm.NewBigInt` and `NumAdd`/`NumSub`/`NumMul`. Machine-integer input is decomposed
in the negative half of the int64 range so MinInt64 never needs an overflowing
absolute-value operation. Quotients truncate toward zero; the remainder has
the dividend's sign.

The pinned `MaybeSimplifyRatio` returns a machine Int for an integral result
that fits int64, BigInt for a larger integral result, and Ratio otherwise.
The Ratio constructor must normalize the denominator's sign and divide both
magnitudes by gcd before applying that rule. BigInt demotion must be explicit
at this boundary, not applied indiscriminately to BigInt arithmetic.
`numeric.bigint/to-long` returns nil outside int64 and accumulates in the
negative range after checking the magnitude against the sign-specific limit.
`numeric.ratio/make-value` rejects a zero denominator, reduces by gcd, makes
the denominator positive, then applies the integral-result rule. The fields
of a nonintegral Ratio are canonical BigInt values.

Native-oracle checks exposed a boundary hidden by ORC/bytecode agreement:
negating a simplified machine MinInt64 wraps, whereas BigInt negation is exact.
The Ratio helper dispatches unary negation by actual simplified type. Exact
rational subtraction uses signed BigInt cross-products directly, so it cannot
inherit that wrapping behavior from an intermediate machine negation.

Runtime integration remains necessary: ordinary deftype instances currently
have generic UserInstance identity, while numeric dispatch in llvm.core only
recognizes Int and Float. Arithmetic dispatch, type predicates, equality/hash,
printing and literal construction must agree on the numeric type descriptors.
Numeric operators must use the shared multimethod mechanism, with BigInt and
Ratio implementations registered as methods. Do not add a separate numeric
callback registry or an opcode switch. Machine-number fast paths must preserve
the shared dispatch semantics and account for method changes. The attempted
callback integration was withdrawn before completion; the verified arithmetic
library remains independent of operator dispatch.

Pooled constants initialize before program-library bodies. Numeric literals
must not call a deftype constructor whose descriptor is still uninitialized;
resolve this startup ordering before enabling their constant-pool lowering.
Keep compiled arithmetic regressions in the existing values fixture once
operator integration is ready; retain native properties in core_test.lg.

## Integration still required

- [x] Implement signed BigInt construction, comparison, negation, addition,
  subtraction, multiplication and quotient/remainder over the limb kernel.
  The existing numeric property group passes against native arbitrary precision;
  ORC matches bytecode for signed boundaries including MinInt64. These checks
  do not establish numeric operator dispatch or literal support.
- [x] Define BigInt sign/limbs and Ratio numerator/denominator through deftype;
  establish pinned return-type and canonicalization rules. Construction and
  exact arithmetic pass the existing native property group and ORC/bytecode
  boundaries, including simplified MinInt64 negation and rational subtraction.
- [ ] Integrate literals, arithmetic, comparison, predicates, hashing, printing,
  evaluator and cache serialization; preserve fast machine-number operations.
- [ ] Verify all jank files without skips and measure arithmetic using the
  existing benchmark harness. BigDecimal and Float32 remain separate required
  work; passing the limb checks does not establish numeric-tower completion.
