# let-go value hashing: port spec

Source: `~/projects-new/3p/let-go` at `4e769212`; paths below are under
`pkg/vm/` unless marked. All arithmetic is wrapping `uint32` unless a step
says `uint64`. `rotl32(x,r) = (x<<r)|(x>>(32-r))`. Test vectors:
`vectors.tsv` (regenerate with `go run . > vectors.tsv`). These algorithms
are **not** Clojure/JVM-compatible, despite comments saying "matching
Clojure"; port these, not Clojure's.

## Entry point

`HashValue(v)` (hash.go:19) → `hashValue` (hash.go:23): if `v` implements
`Hashable` (has `Hash() uint32`, hash.go:15) use that, else `computeHash`
(hash.go:31): `NIL` → 0, anything else → FNV-1a over the bytes of
`v.String()`. The lg builtin `hash` is `int64(HashValue(x))`
(rt/lang.go:8886-8890), so lg sees the uint32 as a **non-negative** int.

## Primitives (hash.go)

| name | definition |
|---|---|
| `hashString(s)` :48 | FNV-1a 32 over the UTF-8 **bytes**: `h=2166136261; for each byte b: h^=b; h*=16777619` (constants :9-10). `hashBytes` :38 is identical over a `[]byte`. |
| `mixK1(k)` :81 | `k*=0xcc9e2d51; k=rotl32(k,15); k*=0x1b873593` |
| `mixH1(h,k)` :88 | `h^=k; h=rotl32(h,13); h=h*5+0xe6546b64` |
| `mixFinishLen(h,len)` :131 | `h^=len; h^=h>>16; h*=0x85ebca6b; h^=h>>13; h*=0xc2b2ae35; h^=h>>16` (Murmur3 fmix32). Note fmix32(0)=0. |
| `mixFinish(h)` :127 | `mixFinishLen(h,0)` |
| `hashUnencodedChars(s)` :67 | seed `h=0`; n = **byte** length. For each byte pair `(s[i-1],s[i])`, i=1,3,5,…: `k = s[i-1] \| s[i]<<16`; `h=mixH1(h,mixK1(k))`. If n is odd, the last byte: `h ^= mixK1(s[n-1])` (no mixH1). Return `mixFinishLen(h, 2*n)`. |
| `hashUint64(v)` :94 | in **uint64**: `v^=v>>33; v*=0xff51afd7ed558ccd; v^=v>>33; v*=0xc4ceb9fe1a85ec53; v^=v>>33`; return low 32 bits. |
| `hashOrdered(seq)` :108 | `h=1; for s=seq; s!=nil; s=s.Next(): h=31*h+hashValue(s.First())`; return `mixFinish(h)`. No length mixed in. |
| `hashUnordered` :118 | sum then mixFinish. **Dead code**: no callers in pkg/. |

`hashUnencodedChars` really is byte-wise: it indexes `s[i]` (Go string
indexing = bytes) and passes `2*len(s)` with `len` in bytes (:67-78; the
comment at :57-66 says so). Non-ASCII therefore hashes its UTF-8 bytes
paired two at a time, *not* runes or UTF-16 units; `héllo` is 6 bytes, an
even count, so it has no tail step. A wasm port can hash the raw UTF-8 bytes
in memory without decoding.

## Per-type dispatch

| value | Hash | file:line | caches? |
|---|---|---|---|
| nil | not Hashable → 0 | hash.go:32-33 | n/a |
| Boolean | true→1, false→0 (raw, not mixed) | bool.go:31 | no |
| Int (int64) | `hashUint64(uint64(n))` | int.go:58 | no |
| Float, Float32 | `hashUint64(IEEE-754 float64 bits)`; no -0/NaN normalisation | float.go:41, :46 | no |
| Char (rune) | `hashUint64(uint64(rune))` | char.go:38 | no |
| String | `hashString` (FNV-1a) | string.go:56 | no |
| Symbol | `hashUnencodedChars(name)` | symbol.go:39 | no |
| Keyword | `hashUnencodedChars(name) + 0x9e3779b9` | keyword.go:38 | no |
| Ratio | `hashUint64(num.Int64())*31 + hashUint64(den.Int64())`, no finaliser; `Int64()` truncates for big parts | ratio.go:62-67 | no |
| BigInt | fits int64 → `hashUint64(n)`; else `h=h*31+b` over big-endian magnitude bytes, `h=^h` if negative | bigint.go:73-87 | no |
| BigDecimal | `hashUint64(bits(Float64()))`, NaN→0, -0→+0 | bigdecimal.go:108-117 | no |
| ArrayVector | own loop: `h=1; h=31*h+hash(e)` per element; `mixFinish` | vector.go:56-62 | no |
| PersistentVector | `hashOrdered(v.Seq())`; empty `Seq()` is `EmptyList` | persistent_vector.go:84-86, :262-264 | no |
| List | `hashOrdered(l)` | list.go:71-78 | yes (`_hash`, list.go:49-50) |
| Cons / ChunkedCons / LazySeq | `hashOrdered`; an empty LazySeq uses `EmptyList` | cons.go:110, chunk.go:221, lazy_seq.go:232-238 | no |
| PersistentMap | `h += hash(k) ^ hash(v)` per entry; `mixFinish(h)`; loop stops at `EmptyList` | persistent_map.go:777-798 | yes (:624-625) |
| SortedMap | same `k^v` sum | sorted_map.go:359-370 | yes |
| PersistentSet | `h += hash(e)`; `mixFinish` | persistent_set.go:69-82 | yes (:18-19) |
| SortedSet | same | sorted_set.go:77 | yes |
| MapEntry | `ArrayVector{k,v}.Hash()` | persistent_map.go:107-109 | no |
| PersistentQueue | empty → 0, else `hashOrdered` | persistent_queue.go:153-158 | no |
| Record | `mixFinish(Σ hash(fieldName)^hash(v) + extra.Hash())` | record.go:142-151 | no |
| Atom, DTypeInstance | identity (pointer): `hashString(%p)`, `mixFinish(uintptr)` | atom.go:230, deftype.go:154 | no |
| Boxed | `hashString(String())` | boxed.go:60-67 | yes |
| UUID / Instant | `hashString(val)` / `hashUint64(UnixMilli)` | uuid.go:88, instant.go:86 | no |
| legacy `vm.Map` | **not Hashable** → FNV of `String()`, which follows Go map order | map.go (no Hash) | no |

The reader produces ArrayVector, List, PersistentMap (its `Type()` reports
`let-go.lang.Map`, persistent_map.go:801) and PersistentSet. A vector with
metadata becomes a PersistentVector (vector.go WithMeta). Keyword and symbol
strings carry no colon; the namespace is part of the hashed string
(`:foo/bar` hashes `"foo/bar"`, keyword.go:48-49).

## Surprises (all reproduced by rows in vectors.tsv)

1. **`hashOrdered` counts `EmptyList` as one `nil` element.** `EmptyList.First()`
   is `NIL` and the loop only stops on Go `nil` (list.go:106-109, :122-125). So
   `()`, `(nil)`, `[nil]` and an empty PersistentVector all hash 1257683291,
   while an empty ArrayVector hashes `mixFinish(1)` = 1364076727. Map and set
   loops guard `s != EmptyList` (persistent_map.go:784), so they don't have this.
2. **Equal values with different hashes.** `(= [] ())` and
   `(= [] (with-meta [] {:a 1}))` are true but the hashes differ (item 1), so
   `(contains? #{[]} ())` is false in lg 4e769212. Likewise `(= 0.0 -0.0)` is
   true but the Float hashes differ (float.go:41 has no -0 fold, unlike
   BigDecimal). `(get {0.0 :z} -0.0)` finds `:z` in a small map but returns
   nil once the map holds 101 entries. These are let-go bugs; the port must
   reproduce them bit-for-bit anyway.
3. **Maps whose every key equals its value hash to 0**, same as `{}`, `#{}`,
   nil, false, `0` and `0.0`: `k^v` cancels (persistent_map.go:794) and
   fmix32(0)=0.
4. **Cross-type collisions by construction.** Int, Char, Float and in-range
   BigInt all go through `hashUint64` on a raw 64-bit pattern: `97` = `\a`,
   `1` = `1N`, `MinInt64` = `-0.0` (both are bit pattern `0x8000…0`), `0` =
   `0.0`. `0.1M` = `0.1`, `1.5M` = `1.5`. Keyword = symbol + 0x9e3779b9, for
   every name (checked on all 29 pairs).
5. Booleans hash to the raw values 1 and 0; `true` collides with nothing in
   the table, but `false` = nil.
6. Every Hashable type agrees with `HashValue`: gen.go aborts if any row's
   `Hash()` differs, and none does. The lg `hash` builtin equals `HashValue`
   on all rows (`checks/hash-parity.sh --self`).
7. Hash depends on the runtime type, not the EDN text: `[]` is two rows
   (`vector`, `pvector`) with different hashes. The check passes `kind` to the
   wasm hook for this reason.
