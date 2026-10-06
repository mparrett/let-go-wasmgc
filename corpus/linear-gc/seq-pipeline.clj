;; Allocates per element through a lazy seq pipeline: the linear M2 benchmark
;; program (docs/LINEAR-TARGET-SPEC.md, decision 3 and phases 2-3)
(println (reduce + (map inc (filter even? (range 2000000)))))
