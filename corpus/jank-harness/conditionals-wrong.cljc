;; checks/jank-suite.sh --self-test: the same reader conditionals asserting
;; the :cljs values, so both sides must report the same three failures.
(ns harness.conditionals-wrong
  (:require [clojure.test :refer [deftest is testing]]))

(deftest reader-conditionals-wrong
  (is (= 2 #?(:clj 1 :cljs 2 :default 3)))
  (is (= 2 #?(:cljs 2 :default 3)))
  (is (= [3] [#?@(:clj [1 2] :cljs [3])])))
