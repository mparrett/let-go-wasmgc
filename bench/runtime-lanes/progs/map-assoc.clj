;; allocates: 2e5 assoc into a persistent hash map
(println (count (loop [i 0 m {}] (if (< i 200000) (recur (inc i) (assoc m i (* i i))) m))))
