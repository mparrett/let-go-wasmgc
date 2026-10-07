;; allocates: 1e6 conj onto a persistent vector, then reduce
(println (reduce + (loop [i 0 v []] (if (< i 1000000) (recur (inc i) (conj v i)) v))))
