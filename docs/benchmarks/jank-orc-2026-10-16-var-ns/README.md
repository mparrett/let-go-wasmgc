# Frozen Var and namespace census

Run 3251 completed: **143/242 deftests, 143/241 files MATCH, no skips**.
The diagnostic bar was zero; exit success does not establish suite compatibility.
Five files failed compilation, one was classified d15, and 92 other files mismatched.

Sources were frozen at `/tmp/jank-integrated-var-ns-20261016`; exact hashes
are in `source-manifest.json`. This snapshot includes Var/watch and namespace
fixes, but predates imported assertion routing, Unicode casing, custom sorted
comparators, variadic not=, and literal identity changes. Two definitions
fixture checks using the runtime cache matched before the census.

Elapsed time was 3154.7 seconds under shared load, not an isolated performance
benchmark. `results.tsv` and `run.log` preserve the full compatibility evidence.
