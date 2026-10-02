;; Transducer pipeline — no intermediate collections
(println (transduce
  (comp (map #(* % %))
        (filter even?))
  + 0
  (range 100000)))
