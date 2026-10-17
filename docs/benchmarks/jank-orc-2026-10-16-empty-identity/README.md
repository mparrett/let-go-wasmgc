# Empty collection identity

Baseline 86061 fails: empty maps/sets compare identical to distinct drained
objects. First fix 75366 uses GC-visible shared empty factories and removes
structural empty-map/set identity shortcuts. The expanded fixture then has
one remaining mismatch: hash-set with zero arguments returns a fresh value.
Its ext wrapper uses into, which intentionally creates a fresh empty set.
Native confirms (hash-set) and (apply hash-set []) share literal identity,
while (into #{} []) does not. Preserve that distinction in the wrapper.

Native runtime regression 25163 and actual jank identical/eq/not_eq 94589
were launched against this initial implementation, before the wrapper fix.
Native runtime 25163 passes 153 tests / 41,975 assertions, zero failures or
errors. Jank 94589 MATCH: 3/3 deftests, 146 assertions, no skips. The initial manifest records that source scope.

The subsequent wrapper change returns the canonical empty set for no items.
The consolidated fixture also distinguishes apply hash-set, into, and set
on empty input. Updated ORC verification 12011 MATCH with reference checking. Cache creation/
restoration with a 1 MiB heap both MATCH (run 34720). The gensym counter remains
1133, and the 722883-byte runtime snapshot writes and reads back successfully.
