# Frozen identity and Unicode census

Run 11513 completed: **150/242 deftests (62.0%)**, **150/241 files MATCH**,
with all 242 definitions attempted and no skips. Seven files improved over
the previous 143-definition census; none regressed. The gains are equality,
identity, not-equals, sorted predicates, capitalization, lower case and upper
case. comparison.json records their exact paths.

The immutable source snapshot is /tmp/jank-identity-integrated-20261017.
This includes Unicode, comparator, equality and empty/literal identity fixes.
It excludes the subsequent user-type and protocol implementation. The manifest
records the frozen inputs; results.tsv and run.log preserve the full result.

The diagnostic bar was zero. A successful command exit does not establish
suite compatibility. The remaining classifications are one compile failure,
one d15 failure, and 89 mismatching files containing 90 test definitions.
These labels are heuristic, not a count of underlying root causes.

Elapsed time was 2,456.1 seconds under shared load with three workers. This
was a compatibility census, not an isolated performance measurement.
