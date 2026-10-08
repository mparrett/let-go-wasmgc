;; checks/jank-suite.sh --self-test (plan review focus 4): .cljc reader
;; conditionals take the :clj branch on both sides of the comparison.
(ns harness.conditionals
  (:require [clojure.test :refer [deftest is testing]]))

(deftest reader-conditionals
  (testing "the :clj branch, the :default branch, and #?@ splicing"
    (is (= 1 #?(:clj 1 :cljs 2 :default 3)))
    (is (= 3 #?(:cljs 2 :default 3)))
    (is (= [1 2] [#?@(:clj [1 2] :cljs [3])]))))
