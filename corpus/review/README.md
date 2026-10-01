# Phase 1 adversarial review (2026-10-01)

Reviewer's brief: break "the backend is correct on the Phase 1 language subset".
Every row was run with `WASM_RUN=checks/wasm-run.sh checks/oracle.sh <file>`
against a snapshot of `src/` at HEAD 4e203f4. Two implementers were editing
`src/` during the review and the working tree stopped compiling even
`corpus/closure/closures.lg` partway through (`unknown type $Str`,
`CompileError`), so results come from HEAD rather than the moving tree. Native lg
is `lg-4e76921230`.

- `probes/` holds every program in the table, as run.
- `bug-NN-*.lg` are the MISMATCH programs (native and wasm output in the header).
- `gap-NN-*.lg` are Phase-2 constructs that fail without a named error.

Classes: MATCH; MISMATCH = inside the Phase 1 scope and native != wasm;
NAMED-LIMIT = refused or thrown with a `lower-wasm: ...` message, or covered by
a DECISIONS entry (D33 stack bound, D42, D52, D63 unbound-var, D65);
GAP = outside Phase 1 and not reported as a named limit; NOT-COMPARABLE =
native does not terminate.

Counts (148 programs, as of 2026-10-01): 78 MATCH, 33 MISMATCH, 28 NAMED-LIMIT, 7 GAP, 2 NOT-COMPARABLE.

## Bugs, ranked (wrong value silently > wrong error > crash)

| # | severity | what | programs | one-line direction |
|---|---|---|---|---|
| bug-02 | wrong value | IR dead-code elimination drops unused checked arithmetic (`+ - * inc dec`, including `(+ nil 1)`), so overflow and type errors vanish. `quot` is kept | p98 p99 q03 q04 q05 | treat checked ops as effectful in the optimize pipeline the backend uses |
| bug-03 | wrong value | LICM hoists `+` and `quot` out of a zero-trip loop: wasm throws `:ovf`/`divide by zero` where native returns 0 | q01 | do not hoist trapping ops past the loop guard |
| bug-04 | wrong value | D35's unary-minus rewrite ignores lexical shadowing: `(let [- inc] (- x))` gives -5 instead of 6 | p14 | skip the rewrite when `-` is locally bound (track locals or rewrite after build) |
| bug-05 | wrong value | `(defn inc ..)` / `(defn + ..)` in `user`: native keeps compiling calls as the core op (prints 2, 7); wasm calls the user defn (101, 12). A native quirk, but the oracle follows native | p16 p17 | reproduce (a D16-style quirk) or refuse by name; record in DECISIONS |
| bug-06 | wrong value | var used before its `def`: native fails `Can't resolve y`, wasm prints `nil` and exits 0 (the driver interns every def up front) | p67 (p85 is the defn-body variant) | intern defs in order, or refuse a forward reference |
| bug-01 | crash | A param that reaches `+ - * < <= > >= inc dec` is typed `i64` in the signature. Call sites (direct and via the defn-as-value wrapper) unbox with `$rt_unbox_int`, a bare `ref.cast`, so passing nil/string/bool traps `illegal cast`. This happens even when the callee guards the value (`(if x (+ x 1) 0)`) or the arithmetic branch is not taken, and `try` cannot catch the trap. Contradicts D42's "no bare ref.cast traps on the boxed path". Hits ordinary nil-guarded optional args and `if-let` | p00a p00b p00c p06 p83 p86 q08 | keep params boxed at the ABI unless every caller provably passes ints, or make the call-site unbox checked and fall back to a boxed entry |
| bug-07 | crash | native lg eliminates tail calls (self and mutual, not just `recur`): 1e7 tail calls finish in 1.7 s. wasm overflows its 256 MB stack. D33 covers deep non-tail recursion only | p38b p39b (p39) | emit `return_call` for calls in tail position |
| bug-08 | crash | `(loop [i 0] (if (< i n) (try (recur (inc i))) i))` is legal natively (prints 3); the driver dies in `ir/build` because the lambda-lifted try region has no loop to recur to | p13 | refuse by name (`recur across try`) or keep tail-recur try regions inline |
| bug-09 | crash | defn names go into wasm ids and exports verbatim: a second `defn f`, a non-ASCII name (`λ`), or a name that collides with the runtime or exports (`mem`, `lgex`, `_main`, `_report`, `print_i64`, `rt_box_int`) fail in wasm-tools or at instantiate | p19 p23 q16-q20 | mangle program ids into their own prefix; last-defn-wins for redefinition |
| bug-10 | wrong error | uncaught thrown string: native pr-str escapes (`"a\"b\nc"`), wasm prints the raw bytes, which also breaks the error line | p88 | escape in `$rt_report` (comment says P2.6; no DECISIONS entry) |
| bug-11 | wrong error | native compile errors (recur not in tail position, recur arity, forward reference) surface as `calling apply` from the driver's eval instead of native's `compiling def value ...`; for p25, native prints `start` before failing and wasm prints nothing | p10 p25 p46 p47 p85 | rethrow the eval error's root message |

## Silent gaps (Phase 2 constructs with no named error)

| # | what | programs |
|---|---|---|
| gap-01 | A non-empty vector literal (`[1 2]`, `[(inc 1)]`), `(list ..)`, a map literal with non-constant values, and `loop`/`let` destructuring all compile to calls of unbound vars, so they report `TypeError: nil is not a function`, which looks like a native error. D63 promises `lower-wasm: Phase-2 constant vector`, but only `[]` gets it | p00d p48 |
| gap-02 | `$rt_print` and `$rt_report` fall through to the Int unbox for `$Fn`, `$Atom` and `$Err`. `(println (fn [] 1))`, `(println (atom 1))`, `(println e)` on a caught exception, and an uncaught `(throw (fn ..))` all trap `illegal cast`, which is uncatchable. Printing them is Phase 2 (D53), but they fail without a name | p57 p58 q06 q07 q14 |

## Named limits worth a DECISIONS note

- D63's runtime surface is the bulk of NAMED-LIMIT here: `not`, `str`, `nil?`, `some?`, `string?`, `rem`, `mod`, `max`/`min`/`abs`, `not=`, `identical?` and `unchecked-inc`/`-dec`/`-negate` all report native's own `TypeError: nil is not a function `. A reader cannot tell that apart from a real native bug.
- `=` throws the named error on any non-Int pair (keyword, nil, bool, string) unless it is constant-folded or part of a 3+ arm keyword `:switch`. A 2-arm `(if (= k :a) ..)` throws. D65 documents only the keyword-cond-in-loop case.
- D33: named-fn closures (`(fn self [n] ..)`, which go through an atom) overflow between 1e5 and 1e6 frames, def'd fns and boxed returns between 1e6 and 3e6. Native handles 3e6.
- `letfn` is refused as `unsupported variadic fn (& args)`, which names the wrong construct.

## Table

| file | direction | result | note |
|---|---|---|---|
| p00a-param-nil-guard | nil-guarded param used in + | MISMATCH bug-01 | param typed i64; (f nil) traps `illegal cast`, uncatchable even in try |
| p00b-param-string-caught | caught type error in + | MISMATCH bug-01 | native catches `cannot add`; wasm traps before try can see it |
| p00c-param-unused-path | param typed by a branch not taken | MISMATCH bug-01 | (sel nil "s") traps although + is never reached |
| p00d-vector-literals | vector literal / destructuring | GAP gap-01 | `[1 2]` reports `TypeError: nil is not a function`, not `Phase-2 constant vector` |
| p01-i31-edge | i31/i64 edge arithmetic | MATCH | ±2^30, 2^31, MinInt64/MaxInt64 mixed, mul_chk edges |
| p02-eq-mixed | = across i31/$Int boundary | MATCH |  |
| p03-loop-cross | loop-carried values crossing i31 | MATCH | incl. 2^62 doubling + overflow |
| p04-closure-cross | captured values crossing i31 | MATCH |  |
| p05-bool-int-ret | recursion returning bool or int | MATCH |  |
| p06-control-macros | cond/and/or/when/if-not/if-let/when-let/loop []/dotimes/while | MISMATCH bug-01 | if-let on nil: (il nil) traps (same param typing) |
| p07-case | case on ints and keywords | NAMED-LIMIT | int case ok; keyword case -> `lower-wasm: = on a non-Int operand` |
| p08-condp | condp | MATCH |  |
| p09-try-recur-catch | try inside loop body, recur after | MATCH |  |
| p10-recur-in-catch | recur from catch (illegal natively) | MISMATCH bug-11 | both fail at compile; wasm says `calling apply`, native `compiling def value` |
| p11-throw-in-finally | throw inside finally | MATCH |  |
| p12-rethrow-different | catch rethrows a different value | NAMED-LIMIT | D63: `str` unbound -> TypeError nil (rethrow itself fine) |
| p13-try-recur | (try (recur ..)) in loop | MISMATCH bug-08 | native prints 3; driver dies in ir/build (recur arity 1 vs 0 in lifted try fn) |
| p14-shadow-minus-unary | local named - called unary | MISMATCH bug-04 | D35 rewrite ignores lexical shadowing: -5/-7 vs 6/6 |
| p15-shadow-plus-let | (let [+ -] ..), (fn [inc] ..) | MATCH | binary shadowing is fine |
| p16-defn-shadow-core | (defn inc ..) in user ns | MISMATCH bug-05 | native keeps calling core inc (2,3); wasm calls user inc (101,102) |
| p17-defn-shadow-core-op-plus | (defn + ..) | MISMATCH bug-05 | native 7, wasm 12 |
| p18-wasm-keyword-names | params named local/global/i64/func, defn end/block | MATCH |  |
| p19-odd-names | ? ! -> ' unicode in names | MISMATCH bug-09 | `λ` -> wasm-tools `empty identifier`; ASCII punctuation fine |
| p20-print-kinds | println of every Phase 1 kind | MATCH |  |
| p21-string-escapes | escapes, unicode, NUL in strings | MATCH |  |
| p22-long-string | 11 KB string literal | MATCH |  |
| p23-defn-twice | two defns same name | MISMATCH bug-09 | wasm-tools `duplicate func identifier`; native prints 1 2 |
| p24-def-novalue | (def x) | MATCH |  |
| p25-throw-before-defn | defn calling a later defn | MISMATCH bug-11 | native prints `start` then compile error; wasm prints nothing, `calling apply` |
| p26-declare-no-def | declare without def, then call | MATCH |  |
| p27-arg-eval-order | side-effecting args | MATCH |  |
| p28-empty-forms | (do) (let []) (loop [] 2) | MATCH |  |
| p29-quot-rem-mod | quot/rem/mod negative | NAMED-LIMIT | quot ok; rem/mod unbound (D63) |
| p30-unchecked | unchecked-negate/inc/dec | NAMED-LIMIT | D63 unbound |
| p30b-neg | (- MinInt64) literal + via param | MATCH | D16/D35 |
| p31-zero-neg0 | (zero? -0) | MATCH |  |
| p32-shifts-boxed | negative/huge shift counts boxed | MATCH |  |
| p33-if300 | 300-arm if chain | MATCH |  |
| p34-cond300 | 300-arm cond | MATCH |  |
| p35-20params | defn with 20 params | MATCH |  |
| p36-nest100 | 100 nested immediately-called fns | MATCH |  |
| p37-curry100 | 100 nested capturing closures | MATCH |  |
| p38-mutual-1e6 | mutual recursion 1e6 via declare | MATCH |  |
| p38b-mutual-1e7 | mutual tail recursion 1e7 | MISMATCH bug-07 | native TCOs (true); wasm `Maximum call stack size exceeded` |
| p39b-tail1e7 | self tail call 1e7 (not recur) | MISMATCH bug-07 | native :done in 1.7 s; wasm stack overflow |
| p40-deep-1e6 | non-tail recursion 1e6 | MATCH |  |
| p41-deep-closure | def'd fn recursion 1e6 | MATCH |  |
| p42-kw-eq | (= :a :a) top level | MATCH | folded; D65 limit is only for unfolded = |
| p43-truthy-consts | (if :kw ..) (if (fn ..) ..) "" 0 {} | MATCH |  |
| p44-anon-pct2 | #(+ %2 1) | MATCH |  |
| p45-variadic-fn | (fn [& r]) | NAMED-LIMIT | `lower-wasm: unsupported variadic fn (& args) as a closure` |
| p46-recur-nontail | recur not in tail | MISMATCH bug-11 | compile error text differs |
| p47-recur-arity | (recur) arity mismatch | MISMATCH bug-11 | compile error text differs |
| p48-loop-destructure | loop [[a b] [1 2]] | GAP gap-01 | TypeError nil instead of a Phase-2 name |
| p49-switch-default-nonkw | switch with default/non-kw scrutinee | MATCH |  |
| p50-d16-together | all D16 quirks in one expression | MATCH |  |
| p51-const-check-min | x + MinInt64, x * -1, literal-first add | MATCH |  |
| p52-typed-loop-overflow | typed loop overflow | MATCH |  |
| p53-cmp-mixed-box | i31 vs $Int boxed compares | MATCH |  |
| p54-eq-various | = on bool/nil/string literals | MATCH | constant-folded |
| p55-eq-strings-fn | = on strings via fn params | NAMED-LIMIT | `= on a non-Int operand` (also nil/bool); D65 understates scope |
| p56-not-eq | not= identical? | NAMED-LIMIT | D63 |
| p57-print-fn-atom | println of an atom | GAP gap-02 | uncatchable `illegal cast` (P2.7 per D53, but not a named error) |
| p58-print-fn | println of a fn | GAP gap-02 | uncatchable `illegal cast` |
| p59-loop-capture-per-iter | per-iteration closure capture | MATCH |  |
| p60-throw-kinds-uncaught | uncaught keyword | MATCH |  |
| p61-throw-int-uncaught | uncaught $Int | MATCH |  |
| p62-throw-nil | throw nil | NAMED-LIMIT | nil? unbound (D63) |
| p63-catch-exception-string | catch-class selection | MATCH |  |
| p64-arity-errors | arity errors direct/value/anon | MATCH |  |
| p65-invoke-nonfn | invoke int/nil/string/bool/atom | MATCH |  |
| p66-def-redef-order | def redefinition order | MATCH |  |
| p67-use-before-def | var used before its def | MISMATCH bug-06 | native: Can't resolve y (exit 1); wasm prints nil, exit 0 |
| p68-int-literals | hex/radix/octal literals | MATCH |  |
| p69-variadic-cmp | (< a b c) | MATCH |  |
| p70-max-min-abs | max min abs | NAMED-LIMIT | D63 |
| p71-inc-nil-caught | inc of nil, caught | NAMED-LIMIT | D42 message |
| p72-case-nomatch | case without default | MATCH |  |
| p73-misc-macros | cond/if-some/when-some/rebinding | NAMED-LIMIT | some? unbound (D63) |
| p74-closure-recur | recur in fn value, closure over loop, try in closure | MATCH |  |
| p75-multiarity-defn | multi-arity defn | NAMED-LIMIT | named |
| p76-defn-private | defn- | NAMED-LIMIT | named (D23) |
| p77-five-param-value | 5-param defn as value | NAMED-LIMIT | named (D52) |
| p78-letfn | letfn | NAMED-LIMIT | named, but says `variadic fn (& args)`: misleading text |
| p79-mixed-if-types | (= r true) | NAMED-LIMIT | = on bool |
| p80-docstring-meta | docstring, ^:private, attr-map | NAMED-LIMIT | attr-map named; docstring/meta fine |
| p81-loop-var-type-change | loop var becomes bool | NAMED-LIMIT | D42 (`+ on a non-Int operand`) |
| p82-bool-nil-phi | bool/nil merges | MATCH |  |
| p83-cmp-param-nil | (< a b) with b nil, caught | MISMATCH bug-01 | trap instead of caught error |
| p84-declare-def-fn | declare + def fn | MATCH |  |
| p85-def-later-defn-ref | defn referencing later def | MISMATCH bug-11 | compile error text differs |
| p86-param-nil-guard-loop | nil-guarded param in loop | MISMATCH bug-01 | native 10 0; wasm trap |
| p87-default-nil-param | nil? guard | NAMED-LIMIT | nil? unbound (D63) |
| p88-uncaught-str-escape | uncaught string with escapes | MISMATCH bug-10 | native `"a\"b\nc"`, wasm raw |
| p89-short-circuit | and/or side effects | MATCH |  |
| p90-try-values | try as value, catch shadowing | MATCH |  |
| p91-try-loop-acc | try in loop accumulating across i31 | MATCH |  |
| p92-finally-order-rethrow | 3-deep finally/rethrow order | MATCH |  |
| p93-catch-overflow-type | catch class vs runtime error | MATCH |  |
| p94-try-in-closure-capture | try inside capturing closure | MATCH |  |
| p95-kw-unicode | unicode keywords, switch | MATCH |  |
| p96-defn-param-same-as-fn | param shadows defn name, dup params | MATCH |  |
| p97-closure-arity-4-5 | closure arity 5 | NAMED-LIMIT | D52 |
| p98-unused-throwing-binding | unused (+ x 1) / (* x 2) | MISMATCH bug-02 | DCE drops overflow: wasm 0 / :ok, native :ovf |
| p99-dead-overflow-fold | unused overflowing literal arithmetic | MISMATCH bug-02 | same |
| q01-licm-overflow | loop-invariant + / quot in 0-trip loop | MISMATCH bug-03 | hoisted: wasm throws :ovf / :dz, native 0 |
| q02-strength-reduce | * 2, * 4, + x x, * 1, * 0 | MATCH |  |
| q03-dead-in-closure | dead overflow in closure | MISMATCH bug-02 |  |
| q04-dead-sub-unary | dead dec / (- x 1) | MISMATCH bug-02 |  |
| q05-dead-boxed | dead (+ nil 1) | MISMATCH bug-02 | type error dropped too |
| q06-print-exinfo | println of ex-info | GAP gap-02 | illegal cast |
| q07-print-caught-overflow | println of caught runtime error | GAP gap-02 | illegal cast |
| q08-param-typed-via-value | typed param via defn-as-value | MISMATCH bug-01 | wrapper unboxes the same way |
| q09-ex-data-print | ex-data/ex-message of non-exceptions | MATCH |  |
| q10-uncaught-exinfo | uncaught ex-info with quotes | MATCH |  |
| q11-uncaught-arity | uncaught arity error via value | MATCH |  |
| q12-uncaught-throw-bool | throw false | MATCH |  |
| q13-uncaught-throw-nil | throw nil | MATCH |  |
| q14-throw-fn-value | uncaught fn value | GAP gap-02 | report falls into rt_print -> illegal cast |
| q16-name-collide-runtime | defn rt_box_int | MISMATCH bug-09 | duplicate func identifier |
| q17-name-collide-export | defn mem | MISMATCH bug-09 | Duplicate export name 'mem' |
| q18-name-collide-main | defn _main | MISMATCH bug-09 | duplicate func identifier |
| q19-name-collide-lgex | defn lgex / _report | MISMATCH bug-09 | Duplicate export name 'lgex' |
| q20-name-collide-import | defn print_i64 | MISMATCH bug-09 | duplicate func identifier |
| q21-mutual-ret-nil | mutual recursion returning nil | MATCH |  |
| q22-def-fn-rebind | def'd fn rebound | MATCH |  |
| q23-defn-in-let | defn inside top-level let | NAMED-LIMIT | `unsupported op :def` |
| q24-comment-ns | ns + comment | MATCH |  |
| q25-self-rec-alias | self call through a let alias | MATCH |  |
| q26-self-rec-typed-nonint-base | D64 optimism with bool base case | MATCH |  |
| q27-local-names | params named tmp/ta/tb/v1/p0 | MATCH |  |
| q28-deep-closure-3e6 | def'd fn recursion 3e6 | NAMED-LIMIT | D33 resource bound (native ok) |
| q29-deep-try-1e6 | try per frame, 1e6 deep | MATCH |  |
| q30-deep-boxed-3e6 | boxed-return recursion 3e6 | NAMED-LIMIT | D33 resource bound; 1e6 (q30b) ok |
| q30b-deep-boxed-1e6 | boxed-return recursion 1e6 | MATCH |  |
| q31-deep-capture-1e6 | named fn (atom) recursion 1e6 | NAMED-LIMIT | D33 bound, but only ~1e5-1e6 for named fns; 1e5 (q31b) ok |
| q31b-deep-capture-1e5 | named fn recursion 1e5 | MATCH |  |
| q32-d42-bitop-param | bit-and on string param | MATCH | bit ops don't type params |
| q33-d42-bitop-boxed-local | bit ops on boxed non-Int | MATCH |  |
| q34-quot-typed-param | quot with nil param | MATCH |  |
| q35-unchecked-param | unchecked-add with bool param | MATCH |  |
| q36-if-guarded-string | string? guard | NAMED-LIMIT | string? unbound (D63) |
| q37-kw-cond-in-loop | keyword cond in loop body | NAMED-LIMIT | D65 |
| q38-throw-then-defn | top-level throw before later defn | MATCH |  |
| q39-eq-kw-local | 2-arm (= k :a) | NAMED-LIMIT | not folded to :switch -> named = error; D65 understates |
| q40-eq-bool-int-boxed | = on bool params | NAMED-LIMIT | named |
| p39-infinite | infinite self tail call (defn f [] (f)) | NOT-COMPARABLE | native never terminates (TCO; killed at 90 s); wasm dies in 1 s with stack overflow. Evidence for bug-07 |
| q15-infinite-nontail | infinite non-tail recursion | NOT-COMPARABLE | native still running at 120 s (Go stack growth); wasm stack overflow |
