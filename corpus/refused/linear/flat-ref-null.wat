;; refuse: unsupported op ref.null (flat instruction) under linear
;; Ungrouped instruction refusal fixture (2026-10-03).
(module
 (type $Bytes (array (mut i8)))
 (type $Bool (struct (field i64)))
 (type $Err (struct (field i32) (field (ref $Bytes)) (field (ref $Bytes)) (field (ref null eq)) (field (ref null eq))))
 (func $flat (result i32) ref.null none ref.test (ref null array)))
