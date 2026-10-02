# review4: adversarial review of the legmacs surface (P6.R, 2026-10-02)

Read-only review of P6.0/P6.1 (D137–D152): per-var binding stacks, the `*err*` fd-2 stack, `set!`,
`$FnX` arities 5..20, top-level defining-`do` splicing, nested defs as var-table vars, boxed
runtime-global inits, the `build-loop` override (P5.12), and the `natives.lg` twins. Nothing in
`src/`, `rt/`, `checks/` or `host/` was touched. All runs used a frozen copy of `src/ rt/ checks/ host/`
taken at 02:25 from joint **86f9fb1 with the uncommitted P6.1 diff** (driver.lg, lower_wasm.lg,
items.tsv, refuse.sh, affected.sh; verified `diff -rq` identical to the live tree and containing
`$FnX`), placed at `<scratch>/ws/dev/lower-wasm` with `corpus/`, `tools/`, `local-scripts/`, `xsofy/`
symlinked so workspace-relative paths resolve. Verdicts: `checks/oracle.sh` via `run.sh` (review3's
driver, per-side timeouts). Test files: `checks/run-tests.sh`. Native lg = `lg-4e76921230`.

Layout: `probes/` oracle programs (a* arity, b* binding, n* ns-init, l* loop/scope, f* natives);
`probes-trap/` one wrong-type call per program, each in a `try`; `lib/r4lib/` library namespaces
(run with `LG_ARGS="-source-paths <abs>/corpus/review4/lib"`); `results*/` verdicts and both outputs
of each MISMATCH; `results/xsofy-P3.2.txt`, `xsofy-P4.2.txt`; `results/legmacs/` native vs module
test output; `bug-NN-*.lg` minimal repros with native's output in the header.
Rerun: `./run.sh <abs paths>` (LW_TREE defaults to the frozen copy).

## Counts (as of 2026-10-02, frozen tree above)

- 67 oracle programs: **38 MATCH, 29 MISMATCH**. Of the 29: 2 harness artifacts (fn address in a
  printed `ex-message`: a09, a10, text otherwise identical); 9 declared limits only (a02/a03 21 params
  refused by name, native has no cap; a05/a11 variadic with more than 4 fixed params, D109; b13
  D149's called-fn print; b19 binding `*print-length*` refused by name; f06 log10 ulp + sin/cos
  Payne-Hanek named limit; f07 D138's empty ns/var table; f02 BigInt literal + `%x` of a float);
  1 native quirk (n05: native's declared-but-undefined fn throws uncatchably at load, the module
  hoists defns and succeeds); n07 is the expected named refusal of `def` in a fn. The rest carry
  the bugs below.
- 49 trap-sweep programs (`probes-trap/`): **43 MATCH**; t45 is bug-02; t33 is bug-10; t04, t19,
  t35, t38 print D42's named numeric-tower text where native says `cannot add/compare ... nil`
  (declared, catchable).
- 11 bug repros: all MISMATCH as described (bug-11 confirmed through probes/f05 only).
- legmacs test files rerun from the frozen tree (`results/legmacs/`): see "Item 6" below.
- **xsofy regression (item 7): HELD.** `run.sh P3.2` 20/20 MATCH (module 1,416,435 B raw); `run.sh P4.2`
  PASS, probe and held walks byte-identical to stock Go at seed 424242.

## Bugs, ranked by blast radius (legmacs first)

| # | class | repro | what / cause hypothesis | proposed row |
|---|---|---|---|---|
| 02 | runtime, uncatchable trap | `bug-02-nth-bad-index-traps.lg` | `nth` with a nil/String/Float index traps (`illegal cast`, escapes `try`); native raises `expected int64, got nil`. This IS the acme_extension_test trap: `buf/insert-string` on a nil state reaches `(nth lines cursor-row)` with both nil. Also `nth` on an array (t45). Contradicts D42 ("no bare ref.cast on the boxed path"): the index is `ref.cast` to i31/Int unguarded | `P6.6 6 oracle on bug-02 + probes-trap/t45` and acme_extension_test reports native's 10 FAIL/1 ERROR set |
| 03 | runtime stub, uncatchable trap | `bug-03-slurp-traps.lg` | `slurp` is still the round-1 `host I/O (Phase 3/4)` trap while D138 gave spit/os/ls/os/stat native's no-such-file behaviour. legmacs loads every file through `(try (slurp path) (catch e nil))` (commands.lg:483: main.lg's file argument and find-file; vibe.lg:531 read-config), so the first find-file in a browser session kills the module | `P6.7 6 oracle on bug-03` (raise `slurp failed: open <p>: no such file or directory`) |
| 05 | reach list gap, named error | `bug-05-reach-list-misses-sleep-promise-delay.lg` | `core/sleep` (main.lg:143 job-poll loop), `core/promise`/`deliver` (buffers.lg jobs) and `core/delay*` have no twin and are absent from `natives-legmacs.txt`, so P6.0's MISSING 0 never saw them. D139's named error fires, but legmacs' main loop dies on its first pending job. Hypothesis: the reach list was built from `legmacs/` sources, not `main.lg` or the tests | `P6.8 6` reach list regenerated over main.lg + test/; `native-twins.sh` MISSING 0 with sleep/promise/deliver/delay* twinned or in SKIP with a reason |
| 01 | backend, silent | `bug-01-defn-variadic-over-4-dropped-as-value.lg` | A defn with another arity plus a variadic of >4 fixed params, used as a value (apply/map/local), silently loses the variadic: `defn-fn-global` drops `vs` when `:fixed > max-var-fixed` and builds a `$FnX`/`$Fn` of the fixed arities, so apply raises a (catchable) arity error. A defn whose only arity is such a variadic is refused by name (a05); this mixed shape should be too, or lowered | `P6.9 6 oracle on bug-01` (match, or a named compile refusal like a05's) |
| 04 | runtime twin, silent | `bug-04-bound-fn-drops-binding.lg` | `bound-fn`/`bound-fn*` return the fn unchanged (rt/wasm/core.lg:1035, "no binding frames until Phase 5"). P6.1 made binding real, so conveyance is silently lost. No legmacs/xsofy use (grep) | `P6.10 6 oracle on bug-04` |
| 10 | twins, D139 gap | `bug-10-interop-static-native-nil-fn.lg` | `(try (Integer/parseInt "x") ...)` raises a native-looking `TypeError: nil is not a function` (review3 bug-07's class); the same call outside a try gives the named `lower-wasm: Integer/parseInt has no twin`. The static-interop call inside an outlined try body takes the value path through the nil slot. No legmacs use | `P6.11 6 oracle on bug-10` (named error inside try too) |
| 08 | runtime twin, wrong error | `bug-08-complement-five-plus-args.lg` | complement's twin fills Fn slots 0..4 with FnInfo k = -1, so 5+ args raise `expected 4294967295 args, got 5` (k printed unsigned). Pre-existing, but 5+ arg calls now lower everywhere. Check rt/wasm/lang.lg:108 (same FnInfo 0 -1 shape) | `P6.12 6 oracle on bug-08 + probes/a12b` |
| 09 | backend, named refusal of a whole program | `bug-09-nested-def-in-case-and-try.lg` | D151 covers defs nested in let/when/if/cond/doseq/when-let (bisected, all MATCH), but a def in a top-level `case` branch is refused (`:def result used as a value`), and one in a top-level `try` or `binding` body (outlined to `_main__tryN_body`, or `<ns>/__lw_nsinit__tryN_body` in a library, probes/n12) gets the in-fn refusal. Not used by legmacs | `P6.13 6 oracle on bug-09` (or record as a named limit in D151) |
| 06 | backend/driver, silent | `bug-06-defonce-reinitialises.lg` | A second `defonce` re-runs its init and overwrites: driver.lg treats `defonce` as `def` (library index! rewrites it). Unused in legmacs/xsofy | `P6.14 6 oracle on bug-06` |
| 07 | twin, error text (P3) | `bug-07-format-bad-verb-ignores-width.lg` | Go pads the value inside a bad-verb report with the width/flags (`%!b(bool=true  )`); `bad-verb` drops them | fold into `P6.15 6 oracle on bug-07 + bug-11` |
| 11 | twin, error text (P3) | `bug-11-json-range-error-path.lg` | read-json's out-of-range number error names the position natively (`into .0 of type float64`); the twin always says `into Go value` | P6.15 |

Cosmetic, not filed: `def` used as a value (`(println (def x 5))`) is a named compile refusal (n04);
the `*print-length*` refusal prints `lower-wasm: lower-wasm:` (b19); the arity>20 refusal for defns
still says "more than 4 params" (a03, a05).

## Item 6: legmacs files still at 0 or partial

- **acme_extension_test**: bug-02 (above). Native itself fails 10 assertions + 1 error here (cwd-relative
  paths); with bug-02 fixed the module should agree with native's FAIL/ERROR set.
- **repl_mode_test** 4/7: the three failing deftests evaluate typed forms (`eval`): Phase 7.
  `eval-errors-print-in-the-transcript` passes for the wrong reason (it expects an `Error:` line and
  gets the no-twin error), worth a note in the P6.2 gate decision.
- **commands_test** (125 vs 132 assertions, so 0 under D143): 5 ERRORs = `/tmp` spit/slurp round trips
  (no FS, D138), `promise` (bug-05), `shell-command` (os/sh, SKIP); the one FAIL is native's own FAIL.
  No other bug.
- **buffers_test** (101 vs 128): 7 ERRORs in the go/future/promise job tests: Phase 7 plus bug-05.

## Claims that HELD

- **binding (D149)**: 12-deep recursive binding, the same var twice in one form, pops on throw from
  nested/called/finally/`dotimes`, `set!` in nested and multi-var bindings, `set!` with no binding,
  native's sequential (not parallel) inits, recur through a binding body, binding values of every kind
  incl. fns, lazy seqs realised after the form (chunked partial realisation), closures called outside,
  `*out*`/`*err*` under `with-out-str` with prints from called fns via println/print/pr/prn/newline/flush/printf,
  throws through with-out-str and `*out*`/`*err*` bindings restore every stack, a var of another ns
  bound from the program and inside the lib: `probes/b01`–`b06`, `b08`–`b12`, `b16`–`b18`, `b09`.
- **$FnX (D150)**: fixed arities 5, 9, 10, 20 as defns and closures, direct/value/apply/map, 20-ary
  with 21 args gives native's error, multi-arity 3/5/variadic(k≤4) incl. exact-arity preference via
  apply, `partial`/`comp`/`juxt` across 4/5, recursion and 10^6 recur at arity 6, letfn mutual
  recursion, closures capturing 6+ locals with 5+ params, `with-meta`/`vary-meta` on 5+ arity fns,
  library 5+ arity defns as values, memoize/fnil/every-pred/some-fn/constantly at 5+ args:
  `probes/a01`, `a06`–`a08`, `a11b`, `a12b` (all but complement), `a13`, `a14`.
- **ns-init (D151)**: defcommand-style `do` with defs and load-time side effects in order, a macro
  expanding to two defs or a let+def, defs nested in let/when/if/cond/doseq/when-let, a def reading
  an earlier global of every kind (map, vector, set, string, float, i64 past 2^53, char, nil, keyword,
  regex), D151's named limit (constant reached through a fn) does NOT reproduce in the main program or
  a library (`n08`, `n11`), library float/char/nil/i64/quoted-collection globals, def order and a lib
  macro across two libraries, defn redefinition seen in order by intervening defs, declare then def:
  `probes/n01`, `n03`, `n08`–`n11`, `n13`, `n04b` (apart from bug-06).
- **Loop/scope after P5.12 (D148)**: shadowing through nested loops, `let` inside loop bodies, closures
  over loop vars, loop in try, recur in case/cond, destructuring loop bindings, same name at four depths,
  no leak of an unshadowed loop var past a global: `probes/l01`–`l08`, all MATCH.
- **natives.lg**: format verbs/width/flags/MISSING/NOVERB/wrong-type (`f01`, most of `f02b`), `lines`,
  `fn?`, `identical?`, `rseq` (`f03`), spit/os/ls/os/stat texts (`f04` apart from slurp), JSON nested,
  unicode, surrogates, escapes, `{:keywords? true}`, write-json float shapes and key order (`f05` apart
  from bug-11), clojure.math tail on edge inputs within the declared limits (`f06`).
- **Uncatchable traps**: 43 of 49 wrong-type calls raise native's catchable text (`probes-trap/`).
