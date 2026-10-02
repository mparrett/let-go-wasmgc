# review5 fix-eval: P7.7 regressions (eval.lg)

Each `bug-NN-*.lg` here is the review5 repro of an evaluator bug fixed by P7.7
(line 1 states native's output); `bug-14c-x08-for-large.lg` is review5's
`probes/deep/x08` (a 20000-element `for`, past the 300 s cap before the fix).
Row: `checks/run-corpus.sh corpus/review5/fix-eval` (all MATCH).

## Not fixed (named limits, for DECISIONS)

- **Bug 11, beyond its three shapes.** The `ExecutionError: calling X` frames
  native adds for every lg-fn call inside a macro are reproduced only where
  review5 found them: `let`/`loop` with a non-seqable binding form
  (`calling destructure*`/`destructure` → `empty?` → `seq`) and the
  `when-let`/`when-first` arity throw (`calling throw`). Any other error
  inside a macro, builtin or evaluated, carries the root message only. E.g.
  `(defmacro thr [] (throw "boom"))` then `(thr)` gives
  `CompileError: Executing macro #'user/thr (<fn thr>) failed\n\tcaused by boom`;
  native gives `... failed\n\tcaused by ExecutionError: calling throw\n\tcaused by "boom"`.
