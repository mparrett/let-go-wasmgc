# review3: adversarial review of the round-1 late mechanisms (P5.R, 2026-10-01)

Read-only review of D122–D127 and the INVENTORY gaps list. Nothing in `src/`, `rt/`,
`checks/` or `host/` was touched. All runs used a frozen copy of `src/ rt/ checks/` from
joint HEAD **1fc6164** (git archive into the reviewer's scratch dir), so implementers' live
edits could not move results. Verdicts come from `checks/oracle.sh` via `run.sh` here (adds
per-side timeouts; a timeout prints `error: TIMEOUT <side>`). Test files went through
`checks/run-tests.sh`. Native lg = `lg-4e76921230`.

Layout: `probes*/` oracle programs as run; `tests/` test-harness probes; `results/` verdicts plus
native/wasm outputs for each MISMATCH; `results-*.txt` batch logs; `bug-NN-*.lg` minimal repros
(expected native output in the header). Rerun: `LW_TREE=<frozen dev/lower-wasm> ./run.sh <abs paths>`.

## Counts (as of 2026-10-01, tree 1fc6164)

- 51 oracle programs: **25 MATCH, 26 MISMATCH**. Of the 26, 6 are harness artifacts or my own mistakes
  (fn addresses in printed error text: c02, s01 before fix; native stack overflow / Ratio /
  native-only fns; `re-matcher`), 3 are declared limits only (r03/r10/r06b `(?i)`/`(?m)`/`\Q`, a04 `to-array`
  family), and the rest carry the bugs below.
- 11 test files through `run-tests.sh`: 1 PASS, 9 FAIL (bugs 08–10), 1 n/a (t05: native aborts too).
- Written, not run before handback: `probes4/c07b-variadic-misc.lg`, `probes5/v10-var-meta-ns.lg`
  (does var meta survive when the program has an `ns` form?), `probes5/r13-re-pattern-in-try.lg`.

## Bugs, ranked by blast radius for xsofy and legmacs

| # | class | repro | what / cause hypothesis | proposed row |
|---|---|---|---|---|
| 01 | backend, silent | `bug-01-literal-regex-is-a-string.lg` | A metachar-free regex literal lowers to a String (D115/P3.2 `literal-regex`), so `replace`/`replace-first` stop expanding `$0`/`$1`, `#""` matches nothing in `re-seq`, `(str #"b")`/`type`/`string?` see a String, and a bad `$1` no longer raises. Every `#"literal"` in legmacs/xsofy gets the wrong `replace` semantics | `P5.6 5 checks/run-corpus.sh corpus/review3/fixed-regex` (literal regexes become the stand-in; bug-01 + r07 MATCH) |
| 02 | backend, silent | `bug-02-posix-class-silent-nil.lg` | `[[:alpha:]]` etc. pass `regex-parse` as a set of the chars `[:alph` and then a literal `]`, so the match returns nil. The parser accepts syntax it doesn't implement. Fix it or refuse it: parse POSIX classes, or reject `[[:` as outside the subset | `P5.7 5 oracle on bug-02 + probes3/r08-posix.lg` |
| 07 | runtime/twins, silent under try | `bug-07-unbound-natives-look-native.lg` | Natives with no twin raise a catchable `TypeError: nil is not a function`, which looks native. legmacs `commands.lg:276` does `(try (re-pattern input) (catch e nil))`, so search would silently match nothing. Unbound in my runs: `re-pattern`, `var?`, `alter-var-root` (legmacs `buffers.lg:530`, xsofy `cheats.lg`), `resolve`/`ns-resolve`/`find-var` (legmacs `vibe.lg:751`), `var-get`, `alter-meta!`/`reset-meta!` (vibe.lg:1047), `with-redefs`, `use-fixtures`, ten `clojure.math` fns, `make-array`/`object-array` | `P5.8 5` an unbound native raises `lower-wasm: <ns/name> has no twin` (named), checked by `native-twins.sh` + bug-07 |
| 05 | backend, silent | `bug-05-reader-meta-dropped.lg` | Reader meta on collection literals is lost, constant or not: `const-form` ignores `(meta v)`, and the const key `[kind pr-str]` would merge `^:a [1]` with `^:b [1]` | `P5.9 5 oracle on bug-05 + probes3/a05-reader-meta.lg` |
| 04 | runtime (lw_ext), hang | `bug-04-regex-exponential-backtracking.lg` | The backtracking matcher is exponential: `(a*)*b` matches with 18 a's but runs past 300 s with 27, while Go is linear. A legmacs regex search over a long line is the exposure | `P5.10 5 timeout 10 checks/wasm-run.sh corpus/review3/bug-04-*.lg` (memoise (node,pos) or Thompson/Pike VM) |
| 06 | backend, wrong value/error | `bug-06-var-standin-shallow.lg` | The var stand-in is a meta'd Symbol. `symbol?` is true. `deref`/call raise native-looking errors although `var-const-form`'s docstring promises named limits. In a no-ns program `:doc`/`:name`/`:line` read nil (v03, v07), against D122's "carrying the var's meta". Hypothesis: the var meta is captured before the `def` form runs | `P5.11 5 oracle on bug-06 + probes/v0*.lg` (minimum: named errors and def meta) |
| 03 | runtime, uncatchable trap | `bug-03-math-round-nan-traps.lg` | `clojure.math/round` of NaN or of a value past Long range hits `i64.trunc_f64_s`, which traps and escapes `try`; native returns 0 / MaxLong. Use `trunc_sat` plus native's clamp | `P5.12 5 oracle on bug-03` |
| 08 | harness, false PASS | `bug-08-test-stub-thrown-passes_test.lg` | A stub or named-limit throw inside `(is (thrown? Exception ..))` counts as a pass: native shows 2 failures, the backend 0 (tests/t01, t10). `run-tests.sh` on one file catches it. The `--corpus` deftest count does not: it counts a deftest as passing when no backend FAIL/ERROR line names it and never compares with native (`run-tests.sh` lines 84–89) | `P5.13 5` corpus counter requires the deftest's FAIL/ERROR set and the file's assertion count to equal native's; check: rerun P5.1 |
| 09 | harness, counts shift | `bug-09-test-unlowerable-deftest-kills-file_test.lg` | A deftest that compiles natively but doesn't lower becomes a stub whose throw escapes `_main` (no `__t-uncaught` wrapper), so the file gets no summary and scores 0 (tests/t02 catch class `ArithmeticException`/`RuntimeException`, t06 `are`, t11) | `P5.14 5 run-tests.sh on bug-09` shows 1 ERROR, not an abort |
| 10 | harness, counts shift | `bug-10-test-shim-semantics_test.lg` | testshim vs native test.lg: a redefined deftest runs twice (t07: Ran 3 vs 2); `is` returns the report value instead of the form's (t03: 5 failures vs 2); `use-fixtures` unbound aborts the file (t04) | `P5.15 5 run-tests.sh corpus/review3/tests/t03*,t07*` PASS |
| 11 | twin gap, wrong error | `bug-11-dissoc-bang-variadic.lg` | `dissoc!` extra-twin has no variadic arity | `P5.16 5 oracle on bug-11` |
| 12 | twin, error text (P3) | `bug-12-array-map-odd-args-message.lg` | `array-map` aliases the hash-map fill, so an odd arg count names the wrong fn | fold into P5.16 |

bug-09/10 headers are taken from the full test files named in the row; the reduced files were not rerun
separately. Not bugs, recorded: `atom :meta` is a named limit that traps uncatchably; `(?i)`, `(?s)`, `(?m)`,
`\Q..\E`, `\x41`, `\pL` and named groups are named limits as declared; variadic closures with more than 4 fixed params are
named (D109, P6.1); native's `letfn` does not eliminate tail calls (1e6 deep overflows the Go stack) while wasm returns, so
those runs are not comparable.

## Claims that HELD

- **Stdlib on first use (claim 1)** for set, walk, zip, data and string: `probes/s01-set` through `s05-string`, `s07-lazy-order`,
  `s08-string-nil` (nil arguments, error text), `probes3/s09-stdlib-more` (custom zippers, meta through
  walk, diff of 9+-key maps, lazy order of side effects). clojure.math is the exception (bugs 03 and 07).
- **array-map past 8 (claim 5)**: key order matches at 9, 12 and 40 keys, string and int keys, assoc, dissoc and into
  (`probes2/a01-array-map`). The memory note that ordering diverges past 8 does not apply to the module. `.getBytes`
  and rt arrays: `probes2/a03-getbytes` MATCH. `meta` twin: `a02` MATCH outside bugs 05 and 11.
- **Closures and variadics (claim 6)**: apply with 0–9 args over 6 variadic shapes stored in a map, `partial`/`comp`/`juxt`/
  `every-pred`/`fnil` over variadics, 5-deep nested capture, letfn mutual recursion, try/catch inside
  loop/recur, deep `cond->`/`some->` recursion: `probes2/c01`, `c02` (address-only diff), `c03`, `c04`, `c05`, `c06` all MATCH.
- **Hash and equality (claim 7)**: mixed numerics, -0.0, NaN, char/string, kw/sym with ns, nested collections as keys,
  conj/disj and assoc/dissoc churn, raw print order of 9+-entry sets and maps, i31/i64 boundaries and float keys:
  `probes2/h01`–`h04`, `probes3/h05` all MATCH.
- **Regex engine on its subset (claim 3)**: `probes3/r09-classes` MATCH (classes, escapes, quantifiers, alternation,
  groups), split limits (`r03`, `r10`) MATCH apart from the declared flags, `(x+x+)+y` stays fast up to 20
  (`probes4/r12-*`).
