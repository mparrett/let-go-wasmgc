;; allocates: lazy seq pipeline, garbage per element
(println (reduce + (map inc (filter even? (range 2000000)))))
