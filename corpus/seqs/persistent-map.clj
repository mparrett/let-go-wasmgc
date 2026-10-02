;; Build a persistent map with 10000 entries
(println (reduce (fn [m i] (assoc m i (* i i)))
        {}
        (range 10000)))
