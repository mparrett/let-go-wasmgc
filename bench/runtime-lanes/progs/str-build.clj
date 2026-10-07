;; allocates: string building
(println (count (apply str (map str (range 200000)))))
