(do (ns wrapped-test (:require [clojure.test :as t :refer [deftest is are]] [library-probe :as helper])))
(defmacro when-available [s & body] `(do ~@body))
(when-available +
  (deftest wrapped (are [a b] (= a b) 1 1 2 2)))
(t/deftest qualified (is (= 3 (+ 1 2))) (helper/check-values =) (helper/imported-test)
  ;; Intentional failures/errors: the oracle must match native reporting too.
  (helper/check-values not=)
  (helper/check-error))
