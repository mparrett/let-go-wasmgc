# FINDINGS (things learned that are not decisions; candidates for later, generic upstream reports)

## Hashing (from corpus/hash/SPEC.md, let-go 4e769212, 2026-09-30)
- H1. `hashOrdered` counts EmptyList as one nil element, so `()`, `(nil)`, `[nil]` and an empty PersistentVector all hash alike, while an empty ArrayVector hashes differently: `(= [] ())` is true but `(contains? #{[]} ())` is false. Looks like a real bug.
- H2. Float hashing does not fold -0.0 into 0.0: `(= 0.0 -0.0)` is true, hashes differ, `(get {0.0 :z} -0.0)` depends on map size. Looks like a real bug.
- H3. Map entries hash as `hash(k) ^ hash(v)`; a map whose keys equal their values hashes to 0, same as `{}`, `#{}`, nil, false, 0, 0.0. Weak, not wrong.
- H4. Int/Char/Float/in-range BigInt share one finalizer: `97` = `\a`, `1` = `1N`, `MinInt64` = `-0.0`; `0.1M` = `0.1`; keyword hash = symbol hash + 0x9e3779b9.
- H5. `hashUnordered` has no callers; legacy `vm.Map` has no Hash() and falls back to FNV of its printed form (Go map order). Not reader-producible.

## Arithmetic (from corpus/opmatrix, D16)
- A1. `(quot MinInt64 -1)` and `(- MinInt64)` wrap silently while sibling forms throw; overflow and divide-by-zero error strings are inconsistently prefixed. Parity for now.

## IR pipeline (from the 2a census)
- I1. Two LICM validation failures on xsofy (`read-dismiss-key!`, `bfs-path`).
- I2. Every structurize fallback on both corpora is the multi-exit loop case.
- I3. lower-go reports "unsupported function body shape" on the probe's `fibl` loop.

## let-go runtime oddities met while writing the reference intrinsics (2026-10-01)
- R1. `(not= ##NaN ##NaN)` is false, so `not=` is not `(not (= …))` for NaN.
- R2. `ns-resolve` returns nil even for public vars; core vars carry no `:ns` meta.
- R3. `bit-or` takes exactly 2 args.
- R4. Shifts follow Go (count not masked): `(bit-shift-right -8 64)` = -1. The wasm backend masks mod 64; the reference intrinsics mirror wasm, lg's own ops mirror lg (D16).

## Maps (from corpus/maporder/SPEC.md, let-go 4e769212, 2026-10-01)
- M1. **Real bug:** when a 2-entry collision bucket loses one key, the survivor is rebuilt at shift 0 regardless of depth (persistent_map.go:552-562): `seq` still shows it, `get` misses it, a re-assoc inserts a duplicate key, `(= c (dissoc a \a))` is false. Pinned by `collide-map.lg` bucket-* rows. Generic upstream report after the campaign.
- M2. With ≤8 keys, `read-json`/transit/bencode-sourced maps take Go map iteration order: native lg is nondeterministic there (2 orders in 3 runs). Not on xsofy's path.
- M3. 11 constructed hash-colliding key pairs incl. an FNV-1a string preimage ("xe2tiazy" collides with 97, \a, 4.8e-322).

## IR build quirks met in P1.0/P1.2 review (2026-10-01)
- I4. build.lg: `(- x)` → `(sub 0 x)` makes `(- MinInt64)` throw where native wraps; lower-go inherits it.
- I5. build.lg: unary comparison `(< x)` is treated as identity, so `(defn f [x] (< x))` returns x, not true. Silent.
- I6. `ir/resolve-single-source` stops at a loop header param fed by the entry value and its own back-edge copy; the backend replaced it with a cycle-following `src-of`.
- I7. structurize's `:fallbacks` counter counts `:multi`-exit loops although their trees are complete (no `:goto`); the 2a census's "3% fallback" is therefore an over-count of real gaps.

## Seqs (rt/wasm/SEQ.md, 2026-10-01)
- S1. Range, InfiniteRange, Repeat and the vector seq do not implement Hashable; `hash` falls back to FNV over the printed form, so `(hash (range 3))` ≠ `(hash '(0 1 2))` although they are `=`. Reproduced.
- S2. `(count (seq (map inc (range 3))))` throws (ChunkedCons has no count); `(peek (cons 1 nil))` throws; a throwing lazy-seq thunk is NOT re-run natively (error cached). Reproduced except the last (needs ex-info, P2.7).
