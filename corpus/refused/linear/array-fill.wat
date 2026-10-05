;; refuse: unsupported op array.fill under linear
;; Out-of-census opcode refusal fixture (2026-10-03).
(module
 (type $Bytes (array (mut i8)))
 (type $Bool (struct (field i64)))
 (type $Err (struct (field i32) (field (ref $Bytes)) (field (ref $Bytes)) (field (ref null eq)) (field (ref null eq))))
 (func $fill (param $a (ref $Bytes))
  (array.fill $Bytes (local.get $a) (i32.const 0) (i32.const 1) (i32.const 1))))
