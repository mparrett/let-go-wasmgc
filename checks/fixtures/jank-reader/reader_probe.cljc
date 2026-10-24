(ns reader-probe (:require [clojure.test :refer [deftest is]]))
(def should-not-be-bound :loaded)
(deftest assertion (is true))
