# review2: differential fuzz of the Phase 2 runtime (rt/wasm/*.lg)

Adversarial review of the claim "rt/wasm/*.lg behaves identically to native let-go on the
Phase 2 surface", run under native lg (`lg-4e76921230`) with the reference intrinsics. Nothing
in `src/`, `rt/` or `checks/` was touched. Run from `dev/lower-wasm/`.

## Counts (2026-10-01, rt/ at 28f7c6d)

- **2300 seeds** run (`[1000,3300)`), 5-40 steps each, 8 shards; ~25 min wall on a host at load
  15-44 from other sessions (per-shard 560-700 s for 400 seeds unloaded-equivalent; logs in `runs/`).
- Plus `seams.lg`: 256 targeted rows, 219 MATCH; every DIFF is accounted for below.
- **105 distinct raw signatures** (`[op field native-class runtime-class]`) in the final runs, plus
  ~3,000 tallied hits on signatures filtered once reported. Hand triage folds them into
  **16 distinct runtime bugs**, 3 declared/known differences, and 3 harness artifacts.
- 19,858 more steps were the README's known follow-up (a static-text `wasm/trap` where native raises
  a catchable error with the same text); 1,564 of those also differ in text because native embeds a
  type name (D47). Tallied, not counted as bugs.

## Method

`fuzz.lg` keeps a pool of `[native runtime]` pairs. A program is a vector of steps: builders
(`:vec-n` at 0/1/2/31/32/33/64/65/1055/1056/1057/1100, `:map-n`/`:set-n` crossing 8/9 with int,
keyword, string, colliding (maporder SPEC M3) and mixed keys in a seeded shuffle, `:tmap-n`
transients with assoc!/dissoc! churn, `:list-n`, 140 leaves covering i31/i64 bounds, -0.0, NaN,
±Inf, subnormals, every escape, multi-byte text, chars, keywords/symbols with and without ns) and
~100 ops over the twins (`tools/twin-manifest.lg`). After every step both results are compared on
pr-str, str, print-str, hash, count, type, meta and a structural bridge; when a step throws, both
must throw and messages are compared (heap addresses normalised). Lazy chains use runtime ports of
core.lg's `take`/`filter`/`concat`/`into` built on the runtime's own seq natives. Pool refs are
taken mod the pool size and the shrinker renumbers them when it deletes a step, so minimal programs
stay meaningful.

```
lg -source-paths rt corpus/review2/fuzz.lg 1000 1400            # a shard (FUZZ_NOSHRINK=1 to skip shrinking)
lg -source-paths rt corpus/review2/fuzz.lg --replay '[[:vec-n 2] [:seq 0]]'
lg -source-paths rt corpus/review2/fuzz.lg --shrink '<prog>' '<sig>'
lg -source-paths rt corpus/review2/fuzz.lg --eval corpus/review2/seams.lg
FUZZ_NOFOUND=1 ...   # turns off the filters for the bugs below, so the fuzzer re-finds them
```

Each `bug-NN-*.lg` runs standalone (`lg -source-paths rt corpus/review2/bug-NN-....lg`) and prints
the native line and the runtime line; its header carries both outputs and the implicated function.

## Distinct bugs, ranked

Rank order: silent wrong value > wrong error > crash/trap > limit that should be parity.
"Hits" counts fuzz steps across all runs, filtered ones included.

| # | rank | file | what | implicated | hits |
|---|---|---|---|---|---|
| 01 | silent | `bug-01-empty-vector-hash.lg` | `(hash [])` is 1257683291 (the `()` hash), native 1364076727; every set or 9+-key map holding `[]` orders differently. H1 is therefore **not mirrored**: runtime `(contains? #{[]} ())` is true, native false | `wasm.seq/hash*` kind 11 via `vec-seq` → EmptyList | 395 |
| 08 | silent | `bug-08-vector-seq-hash.lg` | `(hash (seq [1 2]))`, `(hash (rest v))`: runtime hashes FNV of `"(seq [1 2])"`, native FNV of `"(1 2)"`; only vectors conj'd past 32 match | `wasm.seq/vec-seq` (always PVecSeq), `hash*` kind 10 | 20+ |
| 02 | silent | `bug-02-lazy-error-not-cached.lg` | a lazy seq whose thunk threw re-runs it on the next access and can return values; native caches the error. `(realized? s)` after the throw: native true, runtime false. **S2 seam open** | `wasm.seq/lazy-step` | 525 |
| 09 | silent | `bug-09-pvec-repeat-print-mode.lg` | a meta'd (or >32-conj'd) vector and a Repeat print elements via `String()` natively in every mode: pr-str loses nested map commas, print-str keeps strings/chars quoted. The runtime honours the mode. **D67 seam fails for these two kinds** | wasm.str printer, kinds 11 (with meta) and 9 | 190 |
| 03 | silent | `bug-03-pvecseq-print-type.lg` | seq of a >32-conj'd vector prints `(0 1 …)` and types PersistentList; native prints `(seq [whole vector])`, type Sequence. The runtime's hash of the same value already uses the `(seq [` form, so its own pr-str and hash disagree | wasm.str (no kind 10 arm), `wasm.core/type-id` | 245 |
| 14 | silent | `bug-14-sort-accepts-non-collections.lg` | `(sort (repeat 3 2))`, `(sort (seq (map inc (range 3))))` return sorted lists; native throws "sort expected a Collection" | `wasm.core` `sortable?` accepts kinds 6 and 9 | 2 |
| 16 | silent (stand-in) | `bug-16-computed-nan-hash.lg` | `(hash (- ##Inf ##Inf))` hashes like `##NaN`; native bits differ (0x7FF8…0 vs Go's 0x7FF8…1). Likely vanishes with the real `f64-bits` (D28); re-check then | `wasm.seq/float-bits` | 1 |
| 13 | silent (native quirk) | `bug-13-repeat-type-of-type.lg` | `(type (type (repeat 2 1)))` is `let-go.lang.Repeat` natively, Type in the runtime. Mirror-or-document call, like H1/M1 | `wasm.core/type-of` | 3 |
| 04 | wrong error | `bug-04-transient-map-not-seqable.lg` | a transient map is seqable natively (`seq`, `first`, `reduce`, `into`, `apply`, `nth` with default all work); the runtime raises "don't know how to create ISeq from …TransientMap" | `wasm.core` foreign-seq hook (ckind 32) | 475 |
| 11 | wrong error | `bug-11-foreign-nonseqable-error.lg` | seq natives on a type value, TransientSet or TransientVector raise one generic message where native names the native (`first expected Seq`, `seq expected Seqable`, …); `(nth (type 1) 0 :nf)` raises where native returns `:nf`; `(apply f 5)` says "apply expected Seq" vs native "seq expected Seqable" | `wasm.core` foreign-seq hook, `apply*` | 200 |
| 15 | wrong error | `bug-15-assoc-failed-message-commas.lg` | "assoc failed for key K" embeds `(pr-str K)`; native embeds K's String() (no map commas) | `wasm.core` assoc1/dissoc1 | 1 |
| 07 | trap | `bug-07-nested-lazy-rethrow-traps.lg` | re-reading a lazy seq whose **nested** thunk threw traps "cast failure, expected struct Fn, got null" (native returns `()`); reached by `(concat () transient-map)` printed twice | `wasm.seq/lazy-step` clears the fn slot before `seq-view` can throw | 301 |
| 06 | trap | `bug-06-hash-meta-named-traps.lg` | hash of a meta'd keyword/symbol, or of a type value, traps; a 9+-key map keyed by a meta'd symbol traps on assoc. Native's meta'd hash differs from the bare name's, so delegating is not enough | `wasm.core` foreign-hash (ckind 35, 36) | 507 |
| 05 | trap | `bug-05-print-transient-map-set-traps.lg` | pr-str/str/print-str of a transient map or set traps; native prints `<transient-map count=N>` (transient vectors already work) | `wasm.core` print-foreign | 217 |
| 10 | trap | `bug-10-hash-atom-volatile-fn-traps.lg` | hash of an atom, volatile or fn traps, so does any collection holding one when hashed or put in a set | `wasm.seq/hash*` `:else` | 26 |
| 12 | unprefixed limit | `bug-12-case-mapping-non-ascii-traps.lg` | upper/lower-case of any non-ASCII string traps, even `"日本"` which has no case; `(int ##NaN)` traps too. Neither is parity nor a `lower-wasm:` named limit | `wasm.str` map-ascii, `int` | 13 |

Not bugs, but recorded:

- **R5 open (known)**: map/set seq hashes still ordered in the runtime (450139980 vs 21852162);
  150 top-level hits plus nested ones (`[:cons :hash]`, `[:nest :hash]`, `[:take-rep :hash]`).
- **D69 declared**: `type` of a >32-conj'd vector reports ArrayVector (1,039 hits), and native
  messages that embed `PersistentVector` read `ArrayVector` (248). Bugs 03, 08 and 09 are the
  same unrecorded ArrayVector/PersistentVector split leaking into hash and print, where D69 does not
  cover it.
- **Named limits that fire as declared** (all `lower-wasm:`-prefixed, so not silent): >4-arg calls
  (D52, 65), float `quot`/`mod` (27; D15's float cases are named limits, verified), with-meta on a
  transient (16) or atom (3). `/` has no runtime twin at all (ratios, D15), so it was not fuzzed.
- **Harness artifacts, excluded**: the bridge's own `with-meta` on a keyword makes a value equal
  only to itself (49); heap addresses in printed atoms/volatiles (180); boundary closures hand a
  native fn a list where native passes a Repeat (5); `disj` is not a twin (7).
- **Native findings met on the way (not runtime bugs)**: R8's stamped empty-list meta shows up
  through `pop`/`rest`/`range` returning `()` (955 tallied). An exception thrown while native `=`
  realises a lazy seq escapes `try`/`catch` in some positions at 4e769212, and so does one from a
  `try` inside a vector literal; the harness works around both (comments in `fuzz.lg`).
  `(lazy-seq (lazy-seq (throw …)))` reads as `()` on the second access natively (bug-07 header).

## Seams that held

- **M1** bucket 2→1: all five colliding pairs (`97/\a`, string, keyword, vector, `2^62/2.0`) in a
  9-key map: seq, `get` miss and re-assoc duplicate count all match.
- **D49** transient drain-regrow stays HAMT-ordered; drain-persist-regrow gives the ordered map.
- **D46** string index semantics: `subs`/`nth`/`get`/`count`/`seq`/`index-of`/`last-index-of` over
  ASCII, 2-, 3- and 4-byte text and NUL agree on value and on which calls throw (the throws are
  traps where native raises: the known follow-up).
- **D67** print modes on scalars, maps, sets, lists, entries and ArrayVectors at any nesting
  (the failures are bug-09's two kinds only).
- **D69** metadata kept by conj/assoc/dissoc/disj/pop and dropped by rest/next/seq/into/persistent!/
  vec/subvec on vectors, maps, sets and lists; meta'd keyword `=` and printing; `with-meta` on a
  scalar is the scalar.
- **H2** `-0.0` vs `0.0` keys at ≤8 and >8 keys; NaN keys miss; `nil`/`()` collapse to one key (D50).
- **S1** Range/Repeat FNV hashes; hash/`=` agreement everywhere outside bugs 01/08/16 and R5.
- Transients: use-after-persistent!, interleaved assoc!/dissoc!/conj!, count on all three kinds.
- `reduce` with `reduced` at random points over vectors, lists, lazy and chunked seqs, maps, sets.
- `compare` across kinds, int/float arithmetic incl. overflow and MinInt64 edges, `quot`/`mod` on
  ints, `read-string` round trips of every generated value incl. NaN, -0.0, escapes and colliders
  (no mismatch in 2300 seeds), keyword/symbol/name/namespace construction, `split`/`trim`/
  `replace`/`parse-long`.

## First three to hand the implementer

1. `bug-01-empty-vector-hash.lg`: `[]` is the most common value in xsofy state, and it silently
   reorders any set or large map that holds it.
2. `bug-08-vector-seq-hash.lg`: every `(seq v)`/`(rest v)` of an ordinary vector hashes wrong;
   pairs with 03/09 as one decision about recording ArrayVector vs PersistentVector.
3. `bug-02-lazy-error-not-cached.lg` (with `bug-07`): one function, `lazy-step`, gives a silent
   re-run in the flat case and an uncatchable trap in the nested case.
