(ns library-probe (:require [clojure.test :as t]))
(def should-not-be-bound :loaded)

(defn check-values [eq]
  (t/testing "assertions in an imported helper"
    (t/are [a b] (eq a b) 1 1 2 2)
    (t/is (eq 3 3))))

(t/deftest imported-test (t/is (= 4 4)))

(defn check-error [] (t/is (throw (ex-info "imported assertion error" {}))))
