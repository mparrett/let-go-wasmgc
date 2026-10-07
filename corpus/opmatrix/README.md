# opmatrix: generated op-matrix corpus (P1.1)

Every `.lg` here is generated; don't edit by hand. Regenerate, from `dev/lower-wasm/`:

    $LW_ROOT/lg-bin/lg-ff1e6dac76 corpus/gen-opmatrix.lg corpus/opmatrix/
    checks/run-corpus.sh --update-expected corpus/opmatrix

There is one program per IR builtin op from the `builtin-ops` table in let-go's
`pkg/rt/core/ir/build.lg`. That table has 23 ops: `+ - * quot / bit-and bit-or bit-xor
bit-and-not bit-shift-left bit-shift-right unsigned-bit-shift-right
unchecked-add unchecked-subtract unchecked-multiply < <= > >= = inc dec bit-not`.
Two more programs cover unary `-` (`neg`) and unary `/` (`recip`), because build.lg
lowers those to distinct shapes (`sub 0 x`, `div 1 x`). A binary op whose program
would run past about 400 lines is split into `-1` and `-2` parts.
`not`, `zero?`, `pos?`, `neg?`, `even?` and `odd?` are left out: they are plain
core defns that compile to `:call`, not to a compare op.

Operands: 0, ±1, ±2, ±7, ±2^31, 2^32, 2^62, MaxInt64, MinInt64, 3037000499 and
3037000500. Shift counts: 0 1 31 32 63 64 -1.

Each application appears twice in the same program:

- `typed` uses literal operands, so typeinfer types the op `:int` (unboxed path).
- `boxed` routes operands through `(defn id [x] x)`, so the op is `:unknown`.

Each application runs in its own `try`, so a throwing case prints
`<mode> <op> <a> [<b>] => error: <ex-message>` and the program continues. Every
program exits 0.

## .expected and what the check is

`oracle.sh` is the match relation. It reruns native lg on every invocation and
never reads `.expected`. `<prog>.lg.expected` is a committed snapshot of native
lg's stdout, and it is still checked. Before calling the oracle,
`checks/run-corpus.sh` diffs native stdout against the snapshot and reports
`STALE-EXPECTED` (exit 1) on any difference. That catches two things the oracle
cannot: a hand-edited snapshot, and an lg that changed behaviour under the
corpus. In the second case the oracle would just track the new behaviour and
keep matching. The snapshot check also runs when the backend runner is missing.
Falsified on 2026-09-30: hand-editing one line of `quot-2.lg.expected` gave
`STALE-EXPECTED`, exit 1.

Native behaviours worth knowing (lg 4e769212, typed and boxed agree on every line):

- `(quot MinInt64 -1)` returns MinInt64 with no error. Clojure throws.
- `(- MinInt64)` returns MinInt64 with no error, while `(- MinInt64 1)` and
  `(dec MinInt64)` throw `integer overflow`.
- `(/ MinInt64 -1)` returns the bigint `9223372036854775808N`. Other int/int
  `/` results are ints or ratios (`1/2`, `-7/2`).
- Shift counts of 64 or more, and negative counts, follow Go rather than Java's
  6-bit mask: `(bit-shift-left 1 64)` is 0, `(bit-shift-left 1 -1)` is 0,
  `(bit-shift-right -7 64)` is -1, and `(unsigned-bit-shift-right -1 64)` is 0.
  None of them throw.
- There are two error texts: `ExecutionError: integer overflow` (from
  `+ - * inc dec`) and a bare `divide by zero` (from `quot`, `/` and unary `/`).
