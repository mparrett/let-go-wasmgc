;; Tight loop with tail-call recursion (let-go benchmark/loop-recur.clj, wrapped in println so the oracle can diff it)
(println
 (loop [i 0 acc 0]
   (if (< i 1000000)
     (recur (inc i) (+ acc i))
     acc)))
