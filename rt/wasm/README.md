# rt/wasm — the wasm runtime in the runtime dialect

Six namespaces that load together under native lg as one runtime (P2.9),
with the reference `wasm.intrinsics` standing in for the wasm instructions.
Ground truth is let-go 4e769212. Each file's header states its dialect; the
`dialect` deftest of its test file enforces it.

## Load order and link step

| order | file | ns | requires | owns |
|---|---|---|---|---|
| 1 | `intrinsics.lg` | `wasm.intrinsics` | | the 42 intrinsics, `defstruct`/`defarray`/`deffunc`, `Bytes` (INTRINSICS.md) |
| 2 | `pvec.lg` | `wasm.pvec` | 1 | the persistent vector, `Node` arrays |
| 3 | `seq.lg` | `wasm.seq` | 1 2 | the value model: every box struct, `Fn` (D52), `kind`, `equiv?`, `hash`; seq kinds, chunking, laziness, the seq natives; strings as collections; `float-bits`; the foreign-kind hook slots (SEQ.md) |
| 4 | `str.lg` | `wasm.str` | 1 2 3 | building the scalar boxes, keyword/symbol interning, `str`/`pr-str`/`print-str`, float formatting, the string natives, `compare` (STR.md) |
| 5 | `phm.lg` | `wasm.phm` | 1 2 3 | the persistent/transient map (array-map + HAMT), map hooks (slot 0) |
| 6 | `phs.lg` | `wasm.phs` | 1 3 5 | the persistent/transient set, set hooks (slot 1) |

`seq.lg` requires neither `str.lg` nor the collections, so the value model
has no cycle: anything that must dispatch on a box lives in seq.lg, and the
collections reach seq.lg's generic natives through hooks. The link step is
one call, `(wasm.phs/install-hooks!)`, which registers maps (slot 0) and sets
(slot 1); `wasm.str/set-print-hook!` installs the printer for them.

Runtime globals (D39), one per namespace that has state: `wasm.seq/hooks`
(three Handler slots) and `wasm.str/globals` (intern table, its count, the
print hook).

## Kind table (`wasm.seq/kind`, the one dispatch point)

| # | kind | struct (in seq.lg unless noted) |
|---|---|---|
| 0 | nil | ref.null |
| 1 | int | i31 when it fits 31 bits signed, else `Int` (D41) |
| 2 | EmptyList | `List` with count 0 |
| 3 | List | `List` |
| 4 | Cons | `Cons` |
| 5 | LazySeq | `LazySeq` |
| 6 | ChunkedCons | `ChunkedCons` |
| 7 | Range | `Range` |
| 8 | InfiniteRange | `InfiniteRange` |
| 9 | Repeat | `Repeat` |
| 10 | PVecSeq | `PVecSeq` |
| 11 | PVec | `wasm.pvec/PVec` |
| 12 | ArrayChunk | `ArrayChunk` |
| 13 | ChunkBuffer | `ChunkBuffer` |
| 14 | Reduced | `Reduced` |
| 15 | Bool | `Bool` |
| 16 | Fn | `Fn` (D52: code 0-2, env, code 3-4, `FnInfo`) |
| 17 | Str | `Str` (UTF-8 bytes, cached hash) |
| 18 | foreign | anything else: `wasm.phm/HMap`, `wasm.phs/HSet`, ... via hooks |
| 19 | Char | `Char` |
| 20 | Kw | `Kw` (interned by wasm.str) |
| 21 | Sym | `Sym` (interned by wasm.str) |
| 22 | Float | `Float` |

Equality and hash of every kind follow corpus/hash/SPEC.md (D19). Kind 18
dispatches through per-kind Handlers, slot 0 maps, 1 sets, 2 a generic
fallback (SEQ.md, "Composition hooks").

## Twin markers

Public defns that implement a let-go native carry `^{:twin "core/name"}`
(D58); `lg tools/twin-manifest.lg` lists them and
`checks/native-twins.sh corpus/natives/natives-shared.txt` scores what the
shipped programs reach. One-kind entries (`massoc`, `vnth`, `sconj`, ...)
carry no marker: the dispatching `assoc`/`get`/... entries do not exist yet
(P2.7).

## Checks

Run from `dev/lower-wasm/`:

- `checks/run-intrinsics-native.sh`: every `corpus/intrinsics/*_test.lg`
  in one lg process, against native lg's own answers; exit 0 iff all pass
  and the test count equals the deftest count. Default tier under 90 s;
  `SLOW=1` adds the 10k map/set builds, every map/set path at 1000 keys and
  the 1e6 reduce gate (D51). `checks/gate.sh 2` sets `SLOW=1`.
- `checks/map-order.sh --native`: the map/set iteration-order corpus
  (corpus/maporder) is current against native lg.
- `checks/native-twins.sh <reach-list>`: natives a program reaches that no
  runtime defn claims.
