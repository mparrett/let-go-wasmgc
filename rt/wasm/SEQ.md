# wasm.seq (P2.5 runtime half, 2026-10-01)

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
| 5 | LazySeq | `LazySeq` [fn s done] | lazy_seq.go:16 (PersistentList) | y | walks | | via resolve | ordered; empty = EmptyList, :232 |
| 6 | ChunkedCons | `ChunkedCons` [chunk more] | chunk.go:112 (PersistentList) | y | **no** (count throws) | | y | ordered |
| 7 | Range | `Range` [start end step] | range.go:28 (Range) | y | O(1), :97 | y | y, 32 | **FNV of String()** |
| 8 | InfiniteRange | `InfiniteRange` [start step] | range.go:156 (Range) | y | **no** | | y, 32 | FNV of `"(range ...)"` |
| 9 | Repeat | `Repeat` [i val] | repeat.go:22 (Repeat) | y | `i`, **-1** when infinite | | | FNV of String() (`"()"` when infinite) |
| 10 | PVecSeq | `PVecSeq` [vec i] | persistent_vector.go:183 (Sequence) | y | O(1) | y | y, leaves | FNV of `"(seq [whole vector])"` |
| 11 | PVec | `wasm.pvec/PVec` | PersistentVector | | O(1) | y | | ordered over Seq (empty → EmptyList) |
| 12 | ArrayChunk | `ArrayChunk` [arr off end] | chunk.go:39 | | y | y | | |
| 13 | ChunkBuffer | `ChunkBuffer` [arr n] | chunk.go:225 | | y | | | |
| 14 | Reduced | `Reduced` | reduced.go:6 | | | | | |
| 15 | Bool | `Bool` (stand-in) | Boolean | | | | | 1/0 |
| 16 | Fn | `Fn` (stand-in) | | | | | | |
| 17 | string | `wasm/Bytes` | String | gap | gap | | | |
| 18 | foreign | anything else | maps, sets, ... | via hook | hook | | | hook |

"FNV of String()": Range, InfiniteRange, Repeat and PersistentVectorSeq do
not implement `Hashable`, so `HashValue` falls back to FNV-1a over the printed
form (hash.go:31). `(hash (range 3))` = 3057436279 while `(hash '(0 1 2))` =
3071521495. Reproduced for int/nil elements; other element kinds trap
(printing needs `str`, P2.6).

## Realisation rules (verified)

- A LazySeq's thunk runs once, on the first First/Next/More/Seq/Count; its
  value goes through `Sequable.Seq()` (so a nested LazySeq is resolved and an
  empty collection becomes nil) and an empty result is cached as nil
  (lazy_seq.go:84-150). `realized?` = done or thunk consumed (:38).
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
| `seq` | nil | PVecSeq / nil | trap (chars gap) | hook seq |
| `first` `rest` `next` `second` | nil, `()`, nil, nil | via its seq | trap | via hook seq |
| `count` | 0 | O(1) | trap (Go counts runes) | hook count |
| `nth` | nil / not-found | Indexed path, OOB throws | trap | seq walk via hook |
| `cons` | `(x)` (Cons, more = nil) | Cons onto its seq | trap | Cons onto hook seq |
| `conj` | List `(x)` | `vconj` | "conj expected Collection" | trap (owner's job) |
| `peek`/`pop` | nil | last / `vpop` | error | error |
| `reduce` | init or `(f)` | via chunked seq | trap | via hook seq |
| `vec` | empty pvec | copy | trap | via hook seq |
| `=` | nil = nil only | PersistentVector.Equals (nilListEquivalent) | ref-eq only (gap) | hook equiv |
| `hash` | 0 | ordered | trap | hook hash |

Quirks reproduced on purpose (D19 spirit): `(count (seq (map inc (range 3))))`
throws (ChunkedCons is not Counted); `(count (repeat x))` = -1; `(peek (cons
1 nil))` throws; `(= '(nil) (lazy-seq nil))` is true (the `*List` branch walks
b unresolved, lang.go:1140); `(= [nil] [()])` true but `(= '(nil) '(()))`
false; `pop` on a Cons/LazySeq counts it first (walks to the end); nth3 on a
non-seqable returns not-found while nth2 throws; `(reduce nil :x nil)` = :x.

## Composition hooks

`(set-hooks! seq count equiv hash)` installs four closures (or null) used for
kind 18. equiv is called whenever either side is foreign and must answer
false for cross-kind pairs. phm/phs install theirs at link time; neither
runtime imports the other. Without a hook, a foreign value traps.

## Gaps

- Strings: let-go seqs a string into chars; no char in the value model, so
  string seq/count/first trap with a named message (P2.6). String `=` is ref-eq.
- Value-model stand-ins live in this file: `Int` box, `Bool`, `Fn` closure
  layout (per-arity funcrefs taking the closure first, env in field 3). They
  disagree with phm's `vstub` (which boxes non-i31 values as `HostVal` side
  table entries); P2.2/P1.3 must pick one and both runtimes follow.
- `map*` covers one collection; the multi-coll path (chunkedHeads) is not
  ported. `list`/`conj` are fixed-arity (0-3 / 0-3) pending the backend's
  variadic-native convention. Float range bounds trap (float box, P2.6).
- A thunk that throws is re-run on the next access; Go stores and re-raises
  the error without re-running (lazy_seq.go:59-68). Needs ex-info (P2.7).
- List hash is recomputed, not cached (observationally identical).
- `vec` returns a PVec where Go returns an ArrayVector; PVec is treated as
  PersistentVector for `=`/hash, so an empty pvec hashes like `()` while a
  literal `[]` (ArrayVector) would not. Which vector kind literals become is a
  value-model decision.
- One runtime global (`hooks`), which the backend does not lower yet (D23).
