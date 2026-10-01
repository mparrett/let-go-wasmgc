# corpus/wasm: P2.1 differential oracle programs (D75)

Plain lg programs, one per runtime area. Each prints one labelled line per probe. Native lg
runs let-go's own Go natives. The backend side compiles the program plus `rt/wasm` through
`src/driver.lg`. Match means `checks/oracle.sh`. `.expected` files are native snapshots (D13).

```
checks/run-corpus.sh corpus/wasm              # the 14 programs
checks/run-corpus.sh corpus/wasm/pending      # the backlog (13 files after P2.12)
checks/run-corpus.sh corpus/wasm/pending/variadic   # P2.12's row (9 programs)
checks/run-corpus.sh --update-expected corpus/wasm corpus/wasm/pending corpus/wasm/pending/variadic
```

## P2.12 status (2026-10-01)

Variadics (D83) are in `src/`: user `& rest` fns (closures, defns, multi-arity with a variadic
arm, destructured rest, recur), core.lg's variadic arities, `apply` over any count, and n-ary
natives as values. `pending/variadic/` holds the five variadic files that were in `pending/`
(apply-over-4, core-variadic-closures, letfn, variadic-core, variadic-user) plus four new
programs: user-variadic, apply-spread (0/1/5/50/1000 elements), hof-chains, coll-extra-args.
All nine MATCH. The directory keeps its name because items.tsv's P2.12 row names it.

`merge-with` MATCHes and is folded back into maps.lg. The main programs are 14/14 on the tree
with P2.13's rt (13/14, R5 only, on the rt before it).
Not covered: `%&` (native lg rejects it: `Can't resolve %&`), and a variadic fn wrapped by
`with-meta` (rt's wrapper copies the fixed code slots only, so its variadic arity is lost).

## P2.11 status (2026-10-01)

Backend fixes for F1, F2, F4/F8/F9, F5, F7, review2 bug-16 (the `##NaN` literal's payload)
and constfold's `(* x 0)` identity on floats are in `src/`. On the tree as it stands,
**10/14** programs MATCH. The four that still fail are runtime-side, and `src/` cannot fix them:

- F3 (maps.lg `eq`, sets.lg `eq-vec-vs-list-member`, hashing.lg `agree-nested`): native's
  map/set equality is `valueEquiv`, which is asymmetric. A vector or map on the left decides by
  its own Go `Equals`, so it equals only its own kind. The runtime's `kequiv` uses plain `=`.
  The README's earlier "native-tier run gives false" was wrong: the runtime under native lg
  returns `true` too. The fix is rt patch A in the P2.11 report.
- review-shapes.lg `r2-R5-map-seq-hash`: native map and set seqs are `MapSeq`/`SetSeq`, which
  have no `Hash()` and hash by FNV over the printed form. The runtime builds a Cons chain.
  This needs a new seq kind in rt (open, R5).

With rt patch A+B applied (verified against a patched copy via `LW_RT_DIR`), the result is
13/14 (only R5 fails), and `pending/ifn-callables.lg` MATCHes as well.

Folded back into their programs (marked `;; folded from pending/...`): compare-float,
float-max-min, negate-float, typed-param-float, float-in-fns, float-runtime-arith (floats.lg),
even-odd, iterate (vectors.lg), flatten-list-pred (seqs.lg), hof-wrong-arity (errors.lg),
int-array, nil-into-int-param (xsofy-shapes.lg). pending/ went from 31 files to 19, and each
remaining header carries a dated "Status after P2.11" line.

**Final run: 2026-10-01 07:15–07:28 PDT**, lg-4e76921230, on the working tree as it stood.
Two other agents were editing `src/` and `rt/` throughout, and the driver failed to load
(`unable to load namespace wasm.arrays`) from 07:02 to 07:14. Results can move with their
next edit. Module bytes are for `wasm-opt -O3 --enable-gc --enable-reference-types
--enable-exception-handling --enable-bulk-memory --enable-tail-call`. Since 07:02 the backend
emits `return_call`, so `--enable-tail-call` is now required: without it wasm-opt refuses the
module (`return_call* requires tail calls`). Compile time is driver + wasm-tools on a warm
`.rtlib` cache, on a loaded host. Native time is under 0.1 s for every program.

| program | probes | native s | compile s | raw B | opt B | result | pending split out |
|---|---|---|---|---|---|---|---|
| atoms.lg | 38 | 0.08 | 11.4 | 274007 | 75667 | MATCH | cas-swap-vals, volatile, meta, variadic-user |
| closures-rt.lg | 49 | 0.03 | 7.4 | 272463 | 74720 | MISMATCH `lazy-closures` (F1) | core-variadic-closures, apply-over-4, closures-unbound, variadic-core |
| control-rt.lg | 52 | 0.03 | 9.3 | 285627 | 78528 | MATCH | letfn |
| errors.lg | 52 | 0.03 | 7.5 | 258882 | 70579 | MATCH | static-trap-errors, deref-reduced, hof-wrong-arity, even-odd |
| floats.lg | 43 | 0.03 | 9.9 | 280692 | 74826 | MISMATCH `pr-0` (F2), `nan-in-vec` (F5) | negate-float, float-runtime-arith, float-max-min, float-unbound, float-in-fns, typed-param-float, compare-float |
| hashing.lg | 84 | 0.03 | 9.0 | 261004 | 71675 | MISMATCH `h-list-empty` (F2), `agree-nested` (F3) | none |
| maps.lg | 66 | 0.06 | 9.1 | 276798 | 76956 | MISMATCH `eq` (F3) | assoc-bang, merge-with, variadic-core (merge), empty |
| reader.lg | 89 | 0.04 | 7.5 | 373788 | 96314 | MATCH | none |
| review-shapes.lg | 36 | 0.04 | 7.0 | 273280 | 71970 | MISMATCH, known bugs only (see below) | review-traps |
| seqs.lg | 78 | 0.03 | 6.2 | 294936 | 80703 | MISMATCH `into-list` (F2) | ifn-callables, variadic-core, flatten-list-pred, deref-reduced, iterate |
| sets.lg | 47 | 0.02 | 5.8 | 282843 | 75313 | MISMATCH `eq-vec-vs-list-member` (F3) | disj |
| strings.lg | 68 | 0.02 | 7.1 | 295895 | 78994 | MISMATCH `m-empty` (F2) | strings-unbound |
| vectors.lg | 82 | 0.03 | 5.9 | 298399 | 80985 | MISMATCH `vector?` (F2) | iterate, even-odd, empty, variadic-core, compare-float |
| xsofy-shapes.lg | 45 | 0.04 | 8.1 | 322294 | 87429 | MATCH | ifn-callables, assoc-bang, int-array, nil-into-int-param, apply-over-4, variadic-core, core-variadic-closures |

5/14 MATCH. Every remaining MISMATCH is a stdout difference, and the whole program runs to
the end. Each one traces to F1, F2, F3 or F5 below, or to a known bug in review-shapes.lg.
No main program aborts.

Policy: a construct that aborts the program (compile error, unbound var, trap, named limit)
moved to `pending/<slug>.lg`, with a header naming the construct and the error. Where a main
probe could keep its intent without that construct, it got an equivalent rewrite (for
example, a loop in place of `iterate`, or `(fn [e] (:id e))` in place of `:id`). The original
form lives in pending. A silent value difference stays in the main program, so the program
stays red until the bug is fixed. No probe was deleted.

### pending/ (31 files, as of 07:28)

MATCH now, so these are ready to fold back into their programs (concurrent fixes landed during
this session): `even-odd`, `flatten-list-pred`, `int-array` (xsofy's int-array/aget/aset grid
idiom fully matches), `iterate`, `nil-into-int-param`.

Still failing, grouped:

- **Unbound natives** (`TypeError: nil is not a function`, the D63 shape): `assoc!`/`dissoc!`
  (assoc-bang, which also covers group-by and frequencies), `disj`/`disj!` (disj), `empty`,
  `meta`/`vary-meta` (meta; all D69 keep/drop probes live there), `compare-and-set!`,
  `swap-vals!`, `reset-vals!`, `instance?` (cas-swap-vals), `prn`, `print`, `char?`,
  `identical?`, `parse-double`, `string/join|replace|blank?|capitalize` (strings-unbound),
  `abs`, `float?`, `int?`, `NaN?`, `infinite?`, `long`, `double`, `rem`, `Math/*`
  (float-unbound), `vector` and `hash-map` as apply targets, `fn?`, `ifn?`, `every-pred`
  (closures-unbound).
- **Named limits:** D78 dropped variadic arities (variadic-core: `merge` with 2+ maps, `mapv`,
  `map` and `concat` over several colls, `update-in` with extra args; merge-with). D52: user
  `& rest` fails the whole program at compile time (variadic-user), and `apply` spreading 5+
  args traps (apply-over-4, so `(apply max coll)` breaks for any coll of 5 or more). Core HOFs
  returning variadic closures, i.e. partial, comp, constantly, juxt, fnil, some-fn
  (core-variadic-closures). Deref of a Reduced or a volatile (deref-reduced, volatile). D42
  unary minus on a boxed float (negate-float).
- **Known bugs:** static-text traps (static-trap-errors, the D74 follow-up), letfn (review),
  review2 bug-11 `(apply + 5)` trap and review bug-08 try/recur (review-traps).
- **New:** F4, F6, F7, F8, F9 below (compare-float, float-runtime-arith, float-max-min,
  float-in-fns, ifn-callables, hof-wrong-arity, typed-param-float, negate-float).

## New failures (not in corpus/review or corpus/review2), ranked

Silent wrong value > wrong error > crash/trap > compile error.

**F1 (silent). Two closures capturing same-named locals in different scopes share the capture.**
The second closure reads the first one's final loop value. Renaming the second `i` to `j` fixes it.
```clojure
(def fs (loop [i 0 acc []] (if (= i 4) acc (recur (inc i) (conj acc (fn [] (* i 10)))))))
(println (mapv (fn [f] (f)) fs))                       ; both [0 10 20 30]
(def gs (mapv (fn [i] (fn [x] (+ x i))) [0 1 2]))
(println (mapv (fn [f] (f 100)) gs))                   ; native [100 101 102], backend [104 104 104]
```

**F2 (silent). The constant pool interns literals by `=`, so the first spelling wins.**
`[]` and `'()` collapse into one constant, and so do `0.0` and `-0.0`. This breaks `vector?`,
`into '()`, hash and printing.
```clojure
(println (pr-str []))  (println (pr-str '()))          ; backend: [] then []   (reverse order: () ())
(println [0.0 -0.0])                                   ; native [0.0 -0.0], backend [0.0 0.0]
```

**F3 (silent). Compiled `=` on maps and sets treats vector and list values or members as equal.**
Native is strict inside maps and sets. A native-tier run of `wasm.core/=` gives `false`, so the
difference is in the compiled path.
```clojure
(println (= {:a [1]} {:a (list 1)}) (= #{[1]} #{(list 1)}))   ; native false false, backend true true
```

**F4 (trap). `compare` with any float operand recurses until the stack overflows.**
That takes down `sort` and `sort-by` on floats, `reduce +`/`*` over floats, `==`, and `=` on
boxed NaN/Inf. Native-tier runs of rt/ match (review2), so the likely cause is that the f64
`<`/`+` inside wasm.str/num-cmp and the numeric twins lower to boxed runtime calls that re-enter.
```clojure
(println (compare 1 2.5))            ; native -1, backend: Maximum call stack size exceeded
(println (reduce + [0.5 1]))         ; native 1.5, same overflow
```

**F5 (silent, minor). Vector `=` short-circuits on identical elements.**
Native compares vector elements without an identity check. Native lists do take the shortcut.
```clojure
(def nan ##NaN) (println (= [nan] [nan]))   ; native false, backend true
```

**F6 (trap). Runtime HOF twins reject non-fn callables.**
Direct `(:a m)` works, and so does `filter :a`. The xsofy shape `(map :id ents)` traps.
```clojure
(map :a [{:a 1}])    ; backend: wasm trap: map expected Fn   (also some #{3}, mapv :a, map {..}, map [..])
```

**F7 (trap). A wrong-arity closure invoked by a `reduce` or lazy `map` twin dereferences a null.**
The twin calls the missing `$Code` slot directly. Direct calls, `apply` and `mapv` raise native's
catchable arity error.
```clojure
(try (reduce (fn [a] a) [1 2]) (catch Exception e :caught))   ; backend: dereferencing a null pointer
```

**F8 (trap). `max`/`min` with a float operand: `illegal cast`.** Floats reaching closures or fn
params via a HOF also trap (`(mapv (fn [x] (< x 0.0)) [-1.5])`, `((fn [k] (fn [x] (* k x))) 2.5)`).
```clojure
(println (max 1 2.5))   ; native 2.5, backend: illegal cast
```

**F9 (compile error). Float literal where typeinfer chose i64:**
`unsupported coercion {:from :float, :to :int}`, which fails the whole program. It is the
compile-time sibling of review bug-01.
```clojure
(println (- 1.5))                                 ; unary minus on a float literal
(defn lt [a b] (< a b)) (println (lt 1.5 2.5))   ; float args to a param typed by <
```

Also seen, lower impact: `(println (+ a 0.5))` with `a` a boxed float throws `lower-wasm:
printing this value needs the runtime` (pr-str of the same value works). review2 bug-16 has
flipped direction: the backend now hashes the `##NaN` literal like the computed NaN, where
review2 saw the opposite.

## Known bugs carried by review-shapes.lg (status 07:28)

The following now MATCH on the current tree: review2 bug-01, 02, 03, 04, 08, 09, 11 (first
and nth), 13, 14 and 15; review bug-07 at 1e5 frames. Still MISMATCH: review2 bug-16 and R5,
review bug-02 (DCE drops the checked `+`, both shapes), review bug-03 (LICM gives `divide by
zero` for a zero-trip loop) and review bug-04 (shadowed unary `-`). pending/review-traps.lg
holds review2 bug-11's `(apply + 5)` trap and review bug-08's compile failure.
