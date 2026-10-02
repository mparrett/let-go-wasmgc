;; Map + filter + take pipeline over lazy seqs
(println (reduce + 0
  (take 100
    (filter even?
      (map #(* % %) (range 10000))))))
