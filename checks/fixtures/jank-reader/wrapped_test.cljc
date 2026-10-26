(do (ns wrapped-test (:require [clojure.test :as t :refer [deftest is are]] [library-probe :as helper])))
(defmacro when-available [s & body] `(do ~@body))
(when-available +
  (deftest wrapped (are [a b] (= a b) 1 1 2 2)))
(t/deftest qualified (is (= 3 (+ 1 2))) (helper/check-values =) (helper/imported-test)
  ;; Intentional failures/errors: the oracle must match native reporting too.
  (helper/check-values not=)
  (helper/check-error))
;; A runtime trap (with-meta on a transient is a named limit off native)
;; throws under --test, so the try catches it and the second assertion runs;
;; without --test the trap ends the run. Native never throws here.
(t/deftest trapped (is (= 1 (try (with-meta (transient []) {:a 1}) 1 (catch Exception _ 1)))) (is (= 2 (+ 1 1))))
