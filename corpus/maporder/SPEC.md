# let-go map/set iteration order: port spec

Source: `$LW_ROOT/let-go` at `ff1e6dac`; paths are under `pkg/vm/`
unless marked. Hashing is `../hash/SPEC.md`; everything here assumes the
port's `hashValue` is bit-exact (D19), because past 8 entries order is a
function of key hashes.

## Two representations behind one type

`PersistentMap` (persistent_map.go:619-626) is either

- **ordered mode**: `root == nil`, entries in `okvs` (alternating k/v) in
  insertion order, linear-scan lookup (`ordered()` :629, `okvsIndex` :633);
- **HAMT mode**: `root != nil`, `okvs == nil`.

`arrayMapMaxEntries = 8` (:601). Rules, all in `Assoc`/`Dissoc` (:865-931):

| operation | effect on order |
|---|---|
| assoc new key, count < 8, ordered | appended at the end (:882-885) |
| assoc existing key (any mode) | value replaced in place, position kept (:870-878); same value returns the same map |
| assoc new key, count == 8, ordered | **promote**: `promoteWithAssoc` (:682-700) pushes the 8 entries, in insertion order, then the new one into a fresh HAMT transient (`forceHAMT`). From then on order is hash order. |
| dissoc, ordered | entry removed, the rest keep their order (:904-915) |
| dissoc, HAMT, entries remain | **no demotion**: stays HAMT even at 1 entry (:928-930) |
| dissoc, HAMT, last entry | becomes the empty *ordered* map (:922-927), so regrowing behaves like `{}` |
| `nil` key | allowed (`key == nil` at :866 is Go nil, not lg `nil`) |

Every map constructor goes through these: the reader (`compiler/reader.go:860`,
`NewArrayMap`), compiled map literals (compiler.go:675-720 emits a call to
`array-map` with the read-time map's entries in its `Seq` order), `array-map`
(`NewArrayMap` :743-771, a transient) and **`hash-map`**
(rt/lang.go:5593-5598 → `NewPersistentMap` :723-735, repeated `Assoc`).
Unlike Clojure, `hash-map` with ≤ 8 entries is insertion-ordered too.
`into`, `group-by`, `frequencies` use transients (core.lg:1512-1520,
1725-1732, 1764-1769); `zipmap`, `select-keys` use `assoc` (core.lg:1714,
1665); `merge` is `conj` of each later map, which assocs that map's entries
in its own `seq` order (persistent_map.go:833-850, core.lg:1553-1560).

**Transients** (transient.go:22-207) have the same two modes: ordered while
`count < 8` on insert (:96-99), `forceHAMT` on the 9th distinct key
(:45-63, okvs pushed in insertion order), `dissoc!` in ordered mode keeps
order (:123-128), no demotion, and `persistent!` of an ordered transient hands
over the slice unchanged (:198-201). A HAMT transient drained to 0 keeps
`t.hamt` set (`Dissoc`, :119-140, never clears it). `persistent!` right after
the drain yields `root == nil`, i.e. the empty ordered map; but keys `assoc!`ed
into the same transient after the drain go into a fresh HAMT root (:103-111),
so the result stays hash-ordered even at 8 keys or fewer (D49; corpus row
`transient-drain-regrow`). Otherwise transient and persistent paths produce
identical order (corpus rows `transient`, `transient-dissoc`).

## Sets are always hash-ordered

`PersistentSet` wraps a `PersistentMap` with each element mapped to itself
(persistent_set.go:15-20), but its empty impl is HAMT-mode (`emptySetImpl`,
:29, `root: &hmapBitmapNode{}`), every constructor seeds from it
(`NewPersistentSet` :34-43; `hash-set` = `NewSet`, set.go:197; `set` and
`into #{}` use a transient that is forced to HAMT, transient.go:459-473),
`disj` to empty lands back on `emptySetImpl` (:128-133) and so does
`persistent!` of an empty transient set (transient.go:513-517). So a set of
any size, including `#{:z :y :x}`, iterates in hash order; insertion order
only matters inside a collision bucket. `seq` of a set is the backing map's
keys in node order (:174-200).

## The HAMT

- Branching factor 32: `hmapShift = 5`, `hmapMask = 0x1f` (:16-19). The digit
  at depth d is `(hash >> 5d) & 31`, **least-significant digit first**
  (`hmapMaskFn` :125). Depths 0..6 (the last digit has 2 bits).
- **Only two node kinds**: `hmapBitmapNode` (:139-145) and
  `hmapCollisionNode` (:489-493). There is no Clojure-style `ArrayNode`; a
  bitmap node holds up to 32 slots.
- A bitmap node's array holds one pair per set bit, ordered by bit position:
  index = `popcount(bitmap & (bit-1))` (`hmapIndex` :133). A pair is either
  `[key, val]` (a leaf) or `[nil, child]` (:141-144). New entries are spliced
  in at their index (:222-236; transient :406-438).
- Two keys whose digits agree at this depth are pushed down together by
  `createNode` (:473-485) into a child one level deeper; equal full 32-bit
  hashes make a collision node instead.
- **seq**: `nodeSeq` (:277-293) walks slots 0..31 in order; a leaf emits its
  entry, a child is walked recursively in place (depth-first). `each`
  (:295-311) is the same walk. Since a slot holds a leaf *or* a child, never
  both, there is no inline-vs-child precedence beyond slot index.

**Closed form** (no collisions): HAMT order is ascending order of
`rk(h) = Σ_{d=0..6} ((h >> 5d) & 31) · 32^(6-d)`, i.e. lexicographic on the
5-bit digits from the least significant end. Verified against native lg on
ints (−500..499), 1000 multiples of 4294967311, 10000 entity keywords, 3000
multi-byte strings, 1920 `[x y]` vectors and a reversed 5000-int build, for
both maps and sets. The tree shape depends on history (dissoc never collapses
a single-entry child), but order does not, except for the two cases below.

### Collision buckets (insertion-ordered, history-dependent)

`hmapCollisionNode` keeps an insertion-ordered array:

- created by `createNode` as `[existing, new]` (:474-480, callers :216-219,
  :399-402);
- a new colliding key is **appended** (:527-533);
- `dissoc` from a bucket of ≥ 3 removes in place, order kept (:563-567).

So `(-> m (assoc 97 :i) (assoc \a :c))` walks `97 \a` and the reverse build
walks `\a 97`.

### Bug that changes order and membership: bucket 2 → 1

`dissoc` from a 2-entry bucket rebuilds the survivor as
`(&hmapBitmapNode{}).assoc(0, n.hash, …)` (:552-562): **shift 0, whatever
depth the bucket sits at** (always ≥ 1). The survivor is still walked by
`seq`, but `get`/`contains?` look it up with the digit for the real depth and
miss whenever `(h >> 5d) & 31 ≠ h & 31`. A later `assoc` of either colliding
key goes into a different slot of that node, so the map can then hold the
**same key twice**. Native lg, for the 97/`\a` pair (digits 23 at depth 0, 11
at depth 1) in a 9-keyword map:

    (dissoc a \a)            → seq has 97, (get c 97) = nil, count 10
    (assoc c 97 :again)      → seq has [97 :again] [97 :int], count 11
    (= c (dissoc a \a))      → false
    sets: (conj s 97) after the same disj → 97 twice

`collide-map.lg` pins these (`bucket-*`, `set-bucket-dissoc` rows). Per D19
the port reproduces it; this is a let-go bug to raise upstream after the
campaign. Reachability in xsofy needs two distinct live keys with equal
32-bit hashes in one >8-entry map followed by a dissoc of one: for the
1920-cell `[x y]` maps that is ≈ 1920²/2³³ ≈ 0.04% per full map.

## Reading paths all agree

`seq` builds a `MapSeq` over a materialised entry slice (:1002-1023,
map.go:110-150). `keys`/`vals` are `(map first m)`/`(map second m)` over
`seq` (core.lg:1679-1685), `reduce-kv` reduces the seq (core.lg:337-341),
`doseq` expands to a seq walk (core.lg:1892), printing walks `entries()`
(:804-819). So xsofy's entity walks, e.g. `(doseq [[k v] (or (:entities world) {})] …)`
(world.lg:565) and `(vals (:entities w))` (render.lg:421, spell.lg:72), see
exactly `seq` order. Every map program prints a `views` row asserting
`keys = doseq = seq = reduce-kv = vals` order; all are `true` natively.

xsofy's entity ids are keywords `:<prefix>-<n>` (det.lg:154-163): a floor
with ≤ 8 entities iterates in `assoc` order, above 8 in the keyword-hash
order (`hashUnencodedChars(name) + 0x9e3779b9`). Gas and FOV maps are keyed
by `[x y]` ArrayVectors (ordered hash, hash SPEC). `entity-*.lg` and
`vec-*.lg` cover both.

## Equality and hash ignore order

`Equals` (:1027-1047) checks counts, then that every entry of one map is
found with an equiv value in the other, mode-agnostic. `Hash` (:777-799) is
`mixFinish(Σ hash(k) ^ hash(v))` (D19); sets `mixFinish(Σ hash(e))`
(persistent_set.go:69-82). Neither depends on order, so `=`/`hash` cannot
catch an order bug: the corpus prints keys.

## sorted-map, for contrast

`SortedMap` (sorted_map.go:302-311) orders by comparator (`DefaultCompare`),
not by hash or insertion; `seq` at :495. Not covered here.

## What a port cannot see unless it mirrors it

1. **Hashes** (D19). Order above 8 entries, and for every set, is a pure
   function of the 32-bit hashes except in collision buckets.
2. **The mode boundary**: 8, the no-demotion rule, drain-to-empty → ordered
   (but not inside one transient, D49), sets never ordered. A port that copies Clojure (sets ordered? no; hash-map
   always hashed) or JS `Map` (insertion order always) diverges at size 9 or
   at size 1 for sets.
3. **Collision-bucket history** and the shift-0 rebuild. "Sort by `rk(h)`"
   is not enough: the port must implement the node algorithms literally,
   including `createNode`'s `[existing, new]` order and the bug.
4. **Go map iteration (random per run)** reaches a `PersistentMap` only by
   assoc'ing out of a Go map: `json/read-json` (rt/json.go:39-48),
   transit JSON objects (rt/transit.go:320-332), bencode dicts
   (rt/bencode.go:134-142), boxing a Go map (value.go:254-275) and
   `MapFromGoMap` (map.go:227). With ≤ 8 keys these produce a
   run-to-run-random insertion order in native lg itself
   (`(json/read-json "{\"z\":1,\"y\":2,\"x\":3,\"w\":4}")` printed two
   different orders in three runs). Above 8 the HAMT hides it except in
   collision buckets. None is on xsofy's path and none is in the corpus; a
   port must not "fix" them into a deterministic order and then expect a
   byte match, and the oracle cannot test them.

## The corpus

`gen.lg` writes 14 programs, `<kind>-{map,set}.lg`, kinds `int` (small,
negative, > 2³²), `kw` (plain and namespaced), `entity` (xsofy ids), `str`
(ASCII, 2-, 3- and 4-byte UTF-8), `vec` (`[x y]`), `mixed` (nil, booleans,
ints, keywords, strings, chars, vectors, floats) and `collide`. Sizes
0–9, 16, 33, 100, 1000, 10000. Insertion order is a Fisher-Yates shuffle
driven by `s' = (1103515245·s + 12345) mod 2³¹`, seed `n + 7`.

Map paths: `literal` (quoted constant), `literal-dyn` (runtime values, so
the compiler's `array-map` call), `assoc`, `into`, `zipmap`, `transient`,
`hash-map`, `array-map`, `update` (re-assoc every key), `dissoc-half`,
`assoc-back`, `transient-dissoc`, `merge` (two halves), `drain-regrow`,
`transient-drain-regrow` (drain and regrow 6 keys inside one transient), plus
`views`. Set paths: `literal`, `literal-dyn`, `conj`, `set`, `into`,
`hash-set`, `transient`, `disj-half`, `conj-back`, `transient-disj`,
`drain-regrow`, `map-keys`.

A row is `<path> <n> <count> <keys>`; above 100 keys, `<keys>` is the first
16, the last 16 and `Σ` checksum `a ← (a·1000003 + idx(k) + 1) mod
(2³¹−1)` over the keys' generation indices, in seq order.

Colliding keys (distinct, unequal, same hash; `collide-*.lg`):
`97`/`\a`/`4.8e-322`/`"xe2tiazy"` (one 4-way bucket: Int, Char, Float bits
97, and an FNV-1a preimage), `"snpfo"`/`"s6rja"`, `:kby0z`/`:kcxik`,
`'kby0z`/`'kcxik`, `[97]`/`[\a]`, `4611686018427387904`/`2.0`: 11 pairs in
6 buckets. `1`/`1N` hash alike but are `=`, so they are one key, not a
collision.

Regenerate and check, from `dev/lower-wasm/`:

    checks/map-order.sh --update   # programs + .expected
    checks/map-order.sh --native   # regen to scratch, require byte-identical programs and .expected
    checks/map-order.sh            # the P2.4 row (backend + let-go test)

`SKIP` keeps `gen.lg` out of `run-corpus.sh`.
