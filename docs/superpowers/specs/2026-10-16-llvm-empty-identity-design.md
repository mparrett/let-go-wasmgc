# Shared empty collection identity

Jank identical_qmark fails because llvm.natives/empty-literal? equates all
metadata-free empty maps/sets. The pinned native oracle instead shares the
literal/zero-argument constructor value while dissoc/disj-to-empty returns a
fresh object. Direct native probes return true for literal versus constructor,
false for literal versus drained collection, and true for a drained alias.

Use one GC-visible runtime global for the empty HMap and one for the empty
HSet. Return these from empty-map/empty-set. Constant initialization already
uses those factories. Preserve fresh allocations in dissoc/disj, persistent!,
and with-meta. Then remove map/set structural emptiness from empty-literal?
and rely on reference identity for these types. Keep list/array-vector handling
unchanged: their native identity rules differ. No new identity field, gensym,
or hidden metadata is needed. This also avoids repeatedly allocating empty
constructor values. Runtime source hashes must invalidate cached libraries.

Rejected: changing identical? to ref-eq alone while factories still allocate
would break shared literal identity. Tagging every collection with allocation
provenance adds a representation field when the actual singleton suffices.

Implementation and verification:
1. Extend the existing values fixture with literals/constructors, drained
   aliases, metadata, transient round trips and empty results for maps/sets.
2. Verify the current implementation fails against pinned native execution.
3. Add shared runtime values and remove the structural identity shortcut.
4. Verify the fixture through ORC, actual identical_qmark, relevant native
   runtime collection groups, cache creation/restoration, and gensym/snapshot.
5. Keep compiled sources stable while cache verification runs. Do not claim
   complete jank compatibility from these targeted tests.

The first differential run after singleton factories (75366) narrowed the
remaining mismatch to zero-argument hash-set: its ext wrapper calls into,
whose transient round trip correctly produces a fresh empty object. Return
the canonical literal directly when the variadic input has no sequence.
Explicitly preserve the native distinction between hash-set/apply hash-set
(shared), into (fresh), and set (shared) on empty input. Actual jank identity
and equality pass before this wrapper correction (94589, 3/3, 146 assertions),
so the broader consolidated fixture is necessary to detect the remaining gap.
