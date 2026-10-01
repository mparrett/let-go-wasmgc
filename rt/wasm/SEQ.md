# wasm.seq (P2.5 runtime half, integrated at P2.9, 2026-10-01)

let-go's sequence machinery in the runtime dialect (`seq.lg`, ns `wasm.seq`),
checked against native lg by `corpus/intrinsics/seq_test.lg` via
`checks/run-intrinsics-native.sh`. Ground truth: let-go 4e769212. Paths are
under `pkg/vm/` unless they start with `rt/` (= `pkg/rt/`) or `core.lg`
(= `pkg/rt/core/core.lg`).

## Kind table (`kind`, the one dispatch point)

| # | kind | struct | Go type (`Type()` name) | Seq | Counted | Indexed | chunked | hash |
|---|---|---|---|---|---|---|---|---|
| 0 | nil | null | | | 0 | | | 0 |
| 1 | int | i31 / `Int` | Int | | | | | hashUint64 |
| 2 | EmptyList | `List` count 0 | `*List` (PersistentList), list.go:41 | y | 0 | | | ordered, counts as one nil (H1) |
| 3 | List | `List` [first next count] | list.go:44 | y | O(1) | | | ordered (Go caches; we recompute) |
| 4 | Cons | `Cons` [first more] | cons.go:12 (PersistentList) | y | walks tail, cons.go:76 | | | ordered |
| 5 | LazySeq | `LazySeq` [fn s done err] | lazy_seq.go:16 (PersistentList) | y | walks | | via resolve | ordered; empty = EmptyList, :232 |
| 6 | ChunkedCons | `ChunkedCons` [chunk more] | chunk.go:112 (PersistentList) | y | **no** (count throws) | | y | ordered |
| 7 | Range | `Range` [start end step] | range.go:28 (Range) | y | O(1), :97 | y | y, 32 | **FNV of String()** |
| 8 | InfiniteRange | `InfiniteRange` [start step] | range.go:156 (Range) | y | **no** | | y, 32 | FNV of `"(range ...)"` |
| 9 | Repeat | `Repeat` [i val] | repeat.go:22 (Repeat) | y | `i`, **-1** when infinite | | | FNV of String() (`"()"` when infinite) |
| 10 | PVecSeq | `PVecSeq` [vec i clen] | of a PersistentVector: persistent_vector.go:183 (Sequence); of an ArrayVector: vector.go:198 (PersistentList) | y | O(1) | y | PV: leaves; AV: 1, 2, 4, ... | PV: FNV of `"(seq [whole vector])"`; AV: FNV of `"(e_i ...)"` |
| 11 | PVec | `wasm.pvec/PVec` [... pkind] | ArrayVector (pkind 0) or PersistentVector (1), D73 | | O(1) | y | | ordered over the elements; empty: AV mixFinish(1), PV EmptyList's |
| 12 | ArrayChunk | `ArrayChunk` [arr off end] | chunk.go:39 | | y | y | | |
| 13 | ChunkBuffer | `ChunkBuffer` [arr n] | chunk.go:225 | | y | | | |
| 14 | Reduced | `Reduced` | reduced.go:6 | | | | | |
| 15 | Bool | `Bool` | Boolean | | | | | 1/0 |
| 16 | Fn | `Fn` (D52's `$Fn`) | | | | | | |
| 17 | Str | `Str` [bytes, cached hash] | String | y, List of Chars (string.go:259) | runes | byte-bounded, rune-found | | FNV-1a, cached |
| 18 | foreign | anything else | maps, sets, ... | via hook | hook | | | hook |
| 19 | Char | `Char` [rune] | Char | | | | | hashUint64(rune) |
| 20 | Kw | `Kw` [ns name hash] | Keyword | | | | | stored (symbol hash + 0x9e3779b9) |
| 21 | Sym | `Sym` [ns name hash] | Symbol | | | | | stored |
| 22 | Float | `Float` [f64] | Float | | | | | hashUint64(float-bits) |
| 27 | MapSeq/SetSeq | `ArrSeq` [arr i flavour] | map.go:110 / set.go:131 (PersistentList) | y | O(1) | | | FNV of String() (P2.13, R5) |

The boxes of 17 and 19-22 are declared here (D38, D48) and built by
wasm.str (`mk-str`, `kw-of-bytes`, ...), which owns interning, printing and
the string natives; `kind` tests them right after `Int` because they are the
common map keys. `equiv?` compares them before the identity fast path (one
NaN box is not `=` to itself): Str by bytes, Char by rune, Float by `==`,
Kw/Sym by text; across kinds always false, as native (`(= 1 1.0)` is false).

"FNV of String()": Range, InfiniteRange, Repeat and PersistentVectorSeq do
not implement `Hashable`, so `HashValue` falls back to FNV-1a over the printed
form (hash.go:31). `(hash (range 3))` = 3057436279 while `(hash '(0 1 2))` =
3071521495. Reproduced for int/nil elements; other element kinds trap
(printing lives in wasm.str, which seq.lg cannot require; see Gaps).

## Realisation rules (verified)

- A LazySeq's thunk runs once, on the first First/Next/More/Seq/Count; its
  value goes through `Sequable.Seq()` (so a nested LazySeq is resolved and an
  empty collection becomes nil) and an empty result is cached as nil
  (lazy_seq.go:84-150). `realized?` = done or thunk consumed (:38).
- A thunk that throws stores its error and every later access rethrows it
  without re-running; `realized?` is then true (lazy_seq.go:59-68). When the
  thunk returns but realising its value throws (a nested lazy seq), native
  keeps nothing and the next access reads `()`: mirrored (P2.10, D74).
- `cons`/`rest` never force a lazy tail; `next` does (Cons.Next resolves,
  cons.go:49; ChunkedCons.Next, chunk.go:151). `seqOf` returns a LazySeq
  unresolved (rt/lang.go:1398); `seq` resolves it (rt/lang.go:2247 via
  `Sequable`).
- A thunk returning a non-seqable (e.g. `(lazy-seq 5)`) throws "don't know
  how to create ISeq from let-go.lang.Int" (lazy_seq.go:127).
- `(range n)` with n > 0 is a `Range` (lazy, O(1) count/nth, chunked); with
  n <= 0 or step 0 it is `EmptyList`, never an eager vector (range.go:188,
  rt/lang.go:5772). `(range)` is an `InfiniteRange`. `(repeat n x)` with
  n <= 0 is `EmptyList`; `(repeat x)` is `Repeat` with i = -1
  (rt/lang.go:6792).

## Chunking rules (verified)

- Chunk size is 32 (`rangeChunkSize = nodeCap`, range_chunked.go:11).
  Range chunks materialise up to 32 boxed ints; InfiniteRange always 32;
  PersistentVectorSeq exposes trie leaves and the tail, windowed at the
  current index (persistent_vector_chunked.go:34-82).
- Go natives that consume chunks: `map*` single-coll (mapLazy1 maps a whole
  chunk per thunk and emits a ChunkedCons, rt/lang.go:1480), `reduce`
  (rt/native_prims.go:367; Range takes a no-allocation arithmetic path,
  :438), `some` (:612), `nth` on a seq (nthInSeq, rt/lang.go:1453).
  `vec` (rt/lang.go:2054) and `count` walk element-wise.
- lg-defined core fns that chunk: `filter` (core.lg:523), `take` (whole chunk
  when it fits the quota, element-wise after, :574), `keep` (:1587), `dorun`
  /`doall` (chunk-next, :2748). `drop`, `concat`, `last`, `take-while` do not.
- Measured realisation (native = wasm.seq, both asserted live in the test):
  `(doall (take 3 (map f (range))))` 32; `(first (map f (range 100)))` 32;
  `(first (map f '(1 2 3)))` 1; `(count (take 33 (map f (range))))` 64;
  `(first (filter f (range 100)))` 32; the map-filter gate realises 224.

## Generic natives by input

| native | nil | pvec | string | map/set (foreign) |
|---|---|---|---|---|
| `seq` | nil | PVecSeq / nil | List of Chars / nil | hook seq |
| `first` `rest` `next` `second` | nil, `()`, nil, nil | via its seq | via its seq | via hook seq |
| `count` | 0 | O(1) | runes (lang.go:6105) | hook count |
| `nth` | nil / not-found | Indexed path, OOB throws | byte bound, rune walk; past the last rune nil (string.go:276) | seq walk via hook |
| `cons` | `(x)` (Cons, more = nil) | Cons onto its seq | Cons onto its seq | Cons onto hook seq |
| `conj` | List `(x)` | `vconj` | "conj expected Collection" | trap (owner's job) |
| `peek`/`pop` | nil | last / `vpop` | error | error |
| `reduce` | init or `(f)` | via chunked seq | via its seq | via hook seq |
| `vec` | empty pvec | copy | vector of Chars | via hook seq |
| `=` | nil = nil only | PersistentVector.Equals (nilListEquivalent) | bytes | hook equiv |
| `hash` | 0 | ordered | FNV-1a, cached | hook hash |

Quirks reproduced on purpose (D19 spirit): `(count (seq (map inc (range 3))))`
throws (ChunkedCons is not Counted); `(count (repeat x))` = -1; `(peek (cons
1 nil))` throws; `(= '(nil) (lazy-seq nil))` is true (the `*List` branch walks
b unresolved, lang.go:1140); `(= [nil] [()])` true but `(= '(nil) '(()))`
false; `pop` on a Cons/LazySeq counts it first (walks to the end); nth3 on a
non-seqable returns not-found while nth2 throws; `(reduce nil :x nil)` = :x.

## Composition hooks

Kind 18 dispatches through one `Handler` per slot, so registrations never
overwrite each other: slot 0 maps (`wasm.phm/install-hooks!`), slot 1 sets
(`wasm.phs/install-hooks!`, which also calls phm's), slot 2 the generic
fallback (`set-hooks!`, kept for callers written against the single slot).
A Handler is `[pred seq count equiv hash]`, each a `Fn`; `(set-kind-hooks!
slot pred seq count equiv hash)` registers one, and a null `seq` clears the
slot. For a foreign value, `hook` asks slot 0's pred, then slot 1's, then
takes slot 2 (whose pred is null, matching everything); with nothing
claiming it, the value traps. equiv goes to the handler of whichever side
is foreign (a first) and must answer false for cross-kind pairs. Neither
runtime imports the other's, and seq.lg imports neither.

## Gaps

- `map*` covers one collection; the multi-coll path (chunkedHeads) is not
  ported. `list`/`conj` are fixed-arity (0-3 / 0-3) pending the backend's
  variadic-native convention. Float range bounds trap (`range-int`), as
  does any numeric-tower mixing (P2.7).
- List hash is recomputed, not cached (observationally identical).
- The FNV-of-String() hash of Range/Repeat/PVecSeq over elements that are
  not ints or nil traps: printing is wasm.str's, and seq.lg cannot require
  it. A print hook in seq.lg (as wasm.str has for foreign values) would
  close it.
- One runtime global (`hooks`), which the backend does not lower yet (D23).
