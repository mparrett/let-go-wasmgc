Oracle programs for P6.0/P5.8 twins that MATCH only once the src patch
lands (`src/lw_rt.lg` ext-twins routes `core/format` to lw-ext's old fill,
which wins over rt/wasm/natives.lg's marker, and `re-pattern` needs
lw-ext's regex parser at run time). Run:
`checks/run-corpus.sh corpus/natives/legmacs-twins-src` after applying it.
When the patch is in, move these into `legmacs-twins/` and delete this dir.
