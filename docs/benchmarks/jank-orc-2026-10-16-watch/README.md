# Watch-suite compatibility

Run 80623: LLVM ORC, pinned let-go e9789b7d53, --no-rtlib, no skips. Both files MATCH: 2/2 deftests, 49/49 assertions, no failures or errors. The harness uses --bar 0 for diagnosis; agreement and complete assertion counts establish this focused pass, not exit status alone. This does not establish a new whole-suite score.

The earlier result after agent state support (run 17456) is retained as agent-state-results.tsv: 0/2 deftests, with add-watch reaching 9/33 assertions before unsupported Var watches.

The consolidated definitions program also matches under ORC with a 1 MiB heap (run 74123). Rebuilding the same emitted module with GC tracing (run 34548) records 910 collections and bytecode-identical output; gc-trace.log and definitions-output.txt preserve that evidence. Its LLVM symbol-reference check reports no missing references. Full native runtime tests and gensym/snapshot checks pass (run 40034): 153 tests, 38,130 assertions, counter 1133.

Cache creation and restoration also pass (run 50444): two consecutive definitions-group executions and the atoms group all MATCH using ORC and a 1 MiB heap with the runtime cache enabled. Independent read-only review found no concrete regressions in root/binding separation, watch snapshots, or retained binding globals.

source-manifest.json hashes the source inventory returned by rg --files src rt host checks after these runs. Sources were unchanged during execution. These concurrent runs are correctness evidence, not isolated performance benchmarks.
