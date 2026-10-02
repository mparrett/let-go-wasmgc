# rt/wasm — the wasm runtime in the runtime dialect

Seventeen namespaces that load together under native lg as one runtime (P2.9, P3.1),
with the reference `wasm.intrinsics` standing in for the wasm instructions.
Ground truth is let-go 4e769212. Each file's header states its dialect; the
`dialect` deftest of its test file enforces it.

## Load order and link step

| order | file | ns | requires | owns |
|---|---|---|---|---|
| 1 | `intrinsics.lg` | `wasm.intrinsics` | | the 43 intrinsics, `defstruct`/`defarray`/`deffunc`, `Bytes` (INTRINSICS.md) |
| 2 | `pvec.lg` | `wasm.pvec` | 1 | the persistent vector, `Node` arrays |
| 3 | `seq.lg` | `wasm.seq` | 1 2 | the value model: every box struct, `Fn` (D52), `kind`, `equiv?`, `hash`; seq kinds, chunking, laziness, the seq natives; strings as collections; `float-bits`; the foreign-kind hook slots (SEQ.md) |
| 4 | `str.lg` | `wasm.str` | 1 2 3 | building the scalar boxes, keyword/symbol interning, `str`/`pr-str`/`print-str`, float formatting, the string natives, `compare` (STR.md) |
| 5 | `phm.lg` | `wasm.phm` | 1 2 3 | the persistent/transient map (array-map + HAMT), map hooks (slot 0) |
| 6 | `phs.lg` | `wasm.phs` | 1 2 3 5 | the persistent/transient set, set hooks (slot 1) |
| 7 | `arrays.lg` | `wasm.arrays` | 1-4 | let-go's typed arrays (`int-array` `byte-array` `aget` `aset` `alength` `aclone` `bytes`), the `Arr` struct, and the count/seq/print/get view wasm.core routes to it (kind 37) |
| 8 | `sorted.lg` | `wasm.sorted` | 1-6 | `sorted-map` / `sorted-set` (default comparator) as key-ordered arrays: `SMap`, `SSet`, which wasm.core routes here (kinds 38, 39); the comparator is wasm.core's, through a hook `install!` sets |
| 9 | `core.lg` | `wasm.core` | 1-8 | the generic dispatchers (`assoc` `get` `conj` `nth` `peek` `pop` `transient` ...), numbers as values, `compare`, atom/volatile, meta, exceptions, `apply*`, `sort`, `type`; the link step `install!` |
| 10 | `reader.lg` | `wasm.reader` | 1-9 | `read-string` for data (EDN subset of let-go's data reader) and `read-string*`; per-call state, no global (READER.md) |
| 11 | `math.lg` | `wasm.math` | 1 3 4 9 | `/` `rem`, the bit ops and unchecked arithmetic as values, `float` `float?` `int?` `bigint?` `rand-int`, math/abs sqrt exp pow (Go's portable float algorithms, i.e. lg's wasm build) |
| 12 | `xxhash.lg` | `wasm.xxhash` | 1 3 4 7 | `xxh3/HashSeed` and `xxh3/Hash`: XXH3-64 as github.com/zeebo/xxh3 v1.1.0 computes it |
| 13 | `host.lg` | `wasm.host` | 1 3 4 7 9 | `println` `print` `pr` `prn`, IO handles (`write!` `flush!` `close!`, `out-handle`/`err-handle` for `*out*`/`*err*`), the clocks, timeout channels (`async/timeout`, `async/<!!` = sleep), `js/emit` `js/url-param` |
| 14 | `lang.lg` | `wasm.lang` | 1-4 9 | `iterate`, `transformer-seq*` (`sequence` with a transducer), `->AssertionError` (`assert`) |
| 15 | `term.lg` | `wasm.term` | 1-4 9 | the `term/*` natives as term_wasm.go defines them: ANSI escapes on fd 1, `read-key` / `key-pending?` / `size` over three term intrinsics (`term-read-key` `term-key-pending` `term-size`, D88 imports) defined there, not in `intrinsics.lg` |
| 16 | `natives.lg` | `wasm.natives` | 1 3 4 7 9 10 11 | P6.0/P5.8, in PLAIN lg like `src/lw_ext.lg` (not seq.lg's dialect): `format`, the ns/var table (`all-ns` `in-ns` `alias` `intern` `ns-publics` `resolve` `find-var` `var?` `var-get` `alter-var-root` `alter-meta!` `push-binding!`/`pop-binding!`), `json/read-json` `write-json`, `spit` and `os/cwd` `ls` `stat` (no file system), `let-go.core/lines`, `fn?`, `identical?`, `rseq`, `make-array`, ten `clojure.math` fns |
| 17 | `eval.lg` | `wasm.eval` | 3 4 9 10 16 | P7.0, in PLAIN lg like natives.lg: `eval` (`core/eval`), a closure-compiling evaluator over the reader's data (compiler.go's special forms, core.lg's macros as expanders, CompileError chains as native prints them), the core table (name -> fn value) evaluated code resolves against, cells for evaluated `def`s in wasm.natives' registry, and `install-program-table!` (the backend's program table) |

`seq.lg` requires neither `str.lg` nor the collections, so the value model
has no cycle: anything that must dispatch on a box lives in seq.lg, and the
collections reach seq.lg's generic natives through hooks. The link step is
one call, `(wasm.core/install!)`: maps (slot 0) and sets (slot 1) through
`wasm.phs/install-hooks!`, wasm.core's own foreign values (transients, types,
meta'd keywords/symbols) in the generic slot 2, which foreign values are
seqable (`wasm.seq/set-seqable-hook!`: maps, sets, transient maps; for the
others first/rest/seq/reduce/map raise their own message), the printer
wasm.str uses for
foreign values (`set-print-hook!`, called with a mode: 0 `Value.String()`,
1 `pr-str`, 2 `print-str`; a map's String() has no commas, its pr-str does),
and the printer seq.lg hashes Range/Repeat/PVecSeq elements with
(`wasm.seq/set-print-hook!`, given `wasm.str/value-string`), and the type
namer wasm.arrays and wasm.seq use in their messages for foreign values
(`wasm.arrays/set-type-name-hook!`, `wasm.seq/set-type-name-hook!`: both load
before wasm.core, so they cannot call `type-name`).

File names must match `[a-z_]+\.lg`: `src/lw_rt.lg` reads this table
with that pattern, and a row it cannot match is silently not loaded by the
backend (why the XXH3 file is `xxhash.lg`).

Runtime globals (D39), one per namespace that has state: `wasm.seq/hooks`
(three Handler slots, the hashing printer, the seqable and ifn hooks, the type namer), `wasm.str/globals` (intern
table, its count, the print hook), `wasm.core/globals` (gensym counter,
interned types), `wasm.arrays/globals` (the type-name hook), `wasm.sorted/globals` (the comparator hook),
`wasm.math/globals` (rand-int's xorshift state), `wasm.natives/registry` (the ns/var table, P6.0) and wasm.eval's atoms (`native-tier`, the recur sentinel, its table caches, P7.0; wasm.reader has none: the reader's code hook is the wasm.core var root of `#'wasm.reader/code-hook`), `wasm.xxhash/globals` (the
default secret, built on first use) and `wasm.host/globals` (the stdout and
stderr handles).

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
| 10 | PVecSeq | `PVecSeq` (vec, i, chunk length): PersistentVectorSeq or ArrayVectorSeq, by the vector's pkind |
| 11 | PVec | `wasm.pvec/PVec` (pkind 0 ArrayVector, 1 PersistentVector, D73) |
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
| 23 | MapEntry | `MapEntry` (key, val): what a map's seq yields; = and hash as the 2-vector, but a Seq, and the only thing `key`/`val` accept |
| 24 | Atom | `Atom` (the backend's `$Atom`: one mutable slot) |
| 25 | Volatile | `Volatile` (same shape) |
| 26 | Err | `Err` (the backend's `$Err` plus a cause: kind 0 ex-info / 1 raw / 2 caught, msg, caught msg, data, cause) |
| 27 | MapSeq/SetSeq | `ArrSeq` (arr, i, flavour 0 MapSeq / 1 SetSeq; P2.13, R5): the seq of a map, a set or a transient map, built by phm/phs's seq hooks. PersistentList type, sequential `=`, counted, not chunked; hashes by FNV of String() (no `Hash()`); `conj` on it is native's recovered panic `interface conversion: vm.Seq is *vm.Cons, not *vm.List` |

wasm.core refines kind 18 with `ckind`: 30 map, 31 set, 32 TransientMap
(phm's `HTransient`), 33 TransientSet (`TSet`), 34 TransientVector (`TVec`),
35 a `type` value (`TypeVal`), 36 a keyword/symbol with meta (`MetaNamed`),
37 a typed array (`wasm.arrays/Arr`; also its `type` id). Values of the
namespaces loaded after wasm.core stay plain kind 18 (wasm.host's `Handle`
and `Chan`): they have no `type` name or printed form yet.

Equality and hash of every kind follow corpus/hash/SPEC.md (D19). Kind 18
dispatches through per-kind Handlers, slot 0 maps, 1 sets, 2 a generic
fallback (SEQ.md, "Composition hooks").

## Vector kinds (D73)

A `PVec` records which Go type native lg would hold. Measured against
`lg-4e76921230`; `corpus/intrinsics/vkind_test.lg` checks every row's type,
hash, printed forms and seq view at sizes 0, 1, 31, 32, 33 (and 1057: four
producers by default, all under `SLOW=1`):

| producer | native type |
|---|---|
| literal, `vector`, `(conj)`, `vec` of anything, `subvec`, `read-string`, `assoc`/`pop` of an ArrayVector | ArrayVector at any size |
| `conj` (and `assoc` at the end) onto an ArrayVector | ArrayVector while the result has <= 32 elements, then PersistentVector |
| `conj`/`assoc`/`pop` of a PersistentVector (down to empty) | PersistentVector, meta kept |
| `with-meta` (meta nil included) | PersistentVector |
| `persistent!` (so `into []`, `mapv`, `filterv`, even `into` onto a meta'd vector) | ArrayVector up to 32, else PersistentVector, never meta |
| `sort`, `reverse`, `keys`, `vals`, `rseq` | lists |

What follows from the kind: an empty ArrayVector hashes mixFinish(1)
(1364076727), an empty PersistentVector as `()` (H1); a PersistentVector,
its seq and a Repeat print their elements through `Value.String()` in every
mode; the seq of a PersistentVector is `Sequence`, prints and hashes as
`(seq [whole vector])` and chunks by 32-wide leaf, while the seq of an
ArrayVector is `PersistentList`, prints from i and chunks 1, 2, 4, ...;
`type` and the messages that name a type follow.

`wasm.pvec/varray` turns a trie built by `vconj` into an ArrayVector of any
size. **Backend note:** vector constants and `vector` calls are built as a
`vconj` chain from `empty-vec` (src/lower_wasm.lg:637, :665, :2107); past 32
elements that is now a PersistentVector, where native's literal is an
ArrayVector. Wrapping the chain in `wasm.pvec/varray` restores parity.

## Hashing values with no value hash

Atoms, volatiles and fns hash by pointer natively (a volatile by FNV of a
String() that embeds its address). The runtime has no address and no
per-object id slot (the `$Atom` and `$Fn` layouts are the backend's, D52/D53),
so each of the three kinds hashes to one constant: consistent with identity
equality and stable within a run, but not distinct between objects (a set of
atoms degrades to one collision node). Exceptions, type values, transients
and meta'd keywords/symbols are not Hashable natively either; they hash by
FNV-1a of their String(), here as there.

## Declared differences (P2.10)

- `(hash x)` of a NaN produced by arithmetic: native sees the hardware's
  default NaN (0x7FF8000000000000) while `##NaN` is Go's `math.NaN()`
  (0x7FF8000000000001). The reference `float-bits` cannot see NaN payloads
  and gives every NaN the latter; the real `f64-bits` intrinsic (D28) gives
  the engine's bits, and the backend then has to emit `##NaN` as
  `nan:0x8000000000001`.
- `upper-case`/`lower-case` map ASCII and Latin-1 and pass caseless scripts
  through (CJK, kana, Hangul, Indic, Hebrew/Arabic, symbols, emoji); other
  cased text is a `lower-wasm:` named limit (Unicode case tables not ported).
  `(int ##NaN)` is a named limit (Go leaves it platform-defined).
- The Repeat type's own type is the Repeat type natively
  (`(type (type (repeat 1 1)))`): mirrored, like H1/M1.

## Declared differences (P3.1)

Measured against `lg-4e76921230`; `corpus/intrinsics/xsofy_natives_test.lg`
checks everything else live.

- Arrays: `(seq arr)` is built when called, so a later `aset` is not seen
  through it (native's TypedArraySeq reads as it walks); only int and byte
  arrays exist (`double-array`, `object-array`, and `conj`/`empty` on an
  array, which make an object-array, are absent); calling an array as a fn
  is not routed.
- `float` is a Float holding float64(float32(x)): native's Float32 shares
  its type name, printed form, hash and `=`, but `(compare (float 1) 1.0)`
  throws natively.
- `/` of two Ints with a non-integral quotient (a Ratio) and
  `(/ MinInt64 -1)` (a BigInt) are named limits (D15).
- math/exp and math/pow follow Go's portable algorithms, which is what lg
  computes on wasm; native arm64 lg differs by 1 ulp on some inputs (fused
  multiply-add in exp_arm64.s and in compiled log/pow). Integral-exponent
  pow, sqrt, and xsofy's own exp inputs agree exactly.
- `rand-int` is a fixed-seed xorshift (native is OS-seeded); the
  `System/currentTimeMillis` origin is the host clock's, not the Unix epoch.
- `iterate` is a Cons over a LazySeq: `type` says PersistentList where
  native says Iterate.
- `->AssertionError` is a raw error (kind 1): message and uncaught text
  match; its class does not (native prints `#error {:type
  java.lang.AssertionError ...}`, and `(catch Exception e)` does not catch
  it natively).
- `xxh3/HashSeed` takes a byte-array, a String (its Chars truncated to
  bytes, as the reflection boundary converts it) or nil, with an Int or nil
  seed; other reflection coercions are named limits.
- IO: `flush!` is nil (native Syncs the fd, which fails on a pipe);
  `js/emit` validates the event name but not the data's JSON conversion;
  `js/url-param` is nil, as native off the browser; `let-go.core/now` is a
  named limit. Handles and timeout channels have no `type` name or printed
  form.

## Twin markers

Public defns that implement a let-go native carry `^{:twin "core/name"}`
(D58); `lg tools/twin-manifest.lg` lists them and
`checks/native-twins.sh corpus/natives/natives-shared.txt --exclude 'term/'`
scores what the shipped programs reach (MISSING 0 since P2.7). One-kind
entries (`massoc`, `vnth`, `sconj`, ...) carry no marker; the dispatching
entries do, and where wasm.core's dispatcher supersedes a seq.lg/str.lg one
(`conj`, `nth`, `peek`, `pop`, `compare`) the marker moved to wasm.core.
`open` and `read-string` are named-limit twins: they claim the native and
trap with a `lower-wasm:` message. `slurp` (wasm.natives, D138) raises
native's catchable open-failed text, as `spit` does.

## Errors

Every namespace raises let-go's catchable errors as the backend's exception
value, `(throw (wasm/new sq/Err 1 msg cmsg nil nil))`, with native's exact
text: the backend lowers #'throw to `throw $lgex`. A native called as a value
reports unprefixed messages (msg = cmsg); `inc`/`dec`, being IR-op fns
natively, carry the "ExecutionError: " prefix once caught. Under native lg the
Err is a wasm ref, so only `catch Throwable` sees it. `wasm/trap` is kept for
invariant violations (`wasm.seq:`, `pvec:`, `phm:` prefixes: a hook not linked,
a count that disagrees with its walk) and `lower-wasm:` named limits (D74
sweep, P2.13). Messages that name a type use `wasm.seq/kind-type-name` for
seq.lg's kinds and wasm.core's namer for foreign values (Hooks slot 6,
installed by `install!`). Every test file's `res` tags a reference trap
`[:trap msg]`, apart from `[:err msg]`, so a trap never matches a catchable
native error.

## read-string and edn.lg (plan D8)

`read-string` is a named limit here. The plan (section 1, item 6) routes it
through `pkg/rt/core/edn.lg` compiled by the backend like any program, on the
premise that edn.lg is an lg EDN reader. At 4e769212 it is not: edn.lg's
`read-string` is one line, `(core/read-data-string s)`, a Go native, so
compiling edn.lg buys nothing until there is a reader written in lg. The
route that stays inside the campaign's rules is a reader in the runtime
dialect (or in plain lg compiled by the backend once top-level defs and
`case` chains lower, P1.6) checked against `read-data-string` the way
str.lg's printer is checked against `pr-str`; the float-literal half needs
the inverse of D45's formatter (Go's strconv parse) in the dialect.

## Checks

Run from `dev/lower-wasm/`:

- `checks/run-intrinsics-native.sh`: every `corpus/intrinsics/*_test.lg`
  in one lg process, against native lg's own answers; exit 0 iff all pass
  and the test count equals the deftest count. Default tier under 90 s;
  `SLOW=1` adds the 10k map/set builds, every map/set path at 1000 keys and
  the 1e6 reduce gate (D51). `checks/gate.sh 2` sets `SLOW=1`.
- `checks/map-order.sh --native`: the map/set iteration-order corpus
  (corpus/maporder) is current against native lg.
- `checks/native-twins.sh <reach-list> [--exclude REGEX]`: natives a program
  reaches that no runtime defn claims.
