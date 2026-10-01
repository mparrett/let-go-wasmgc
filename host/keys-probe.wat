;; keys-probe.wat — exercises the term.* imports (host/ABI.md) until the
;; backend lowers term/read-key (Phase 4). Same export names as an emitted
;; module, so every host runs it unchanged.
;;
;; Prints "size <cols> <rows>", "ready", then one "key <byte> ..." line per
;; key until a lone `q`, then "pending <key_pending>" and "bye". End of input
;; before `q` prints "eof". Key buffer at 64, strings at 128.
(module
  (import "term" "read_key" (func $read_key (param i32 i32) (result i32)))
  (import "term" "key_pending" (func $key_pending (result i32)))
  (import "term" "size" (func $size (result i32 i32)))
  (import "env" "print_i64" (func $print_i64 (param i64)))
  (import "env" "print_str" (func $print_str (param i32 i32)))
  (import "env" "print_nl" (func $print_nl))
  (memory (export "lw mem") 1)
  (data (i32.const 128) "size ")      ;; 128..132
  (data (i32.const 136) "ready")      ;; 136..140
  (data (i32.const 144) "key")        ;; 144..146
  (data (i32.const 148) " ")          ;; 148
  (data (i32.const 152) "pending ")   ;; 152..159
  (data (i32.const 160) "bye")        ;; 160..162
  (data (i32.const 164) "eof")        ;; 164..166
  (func $main (export "lw main") (local $n i32) (local $i i32) (local $c i32) (local $r i32)
    (call $size) (local.set $r) (local.set $c)
    (call $print_str (i32.const 128) (i32.const 5))
    (call $print_i64 (i64.extend_i32_s (local.get $c)))
    (call $print_str (i32.const 148) (i32.const 1))
    (call $print_i64 (i64.extend_i32_s (local.get $r)))
    (call $print_nl)
    (call $print_str (i32.const 136) (i32.const 5))
    (call $print_nl)
    (block $out (loop $l
      (local.set $n (call $read_key (i32.const 64) (i32.const 16)))
      (if (i32.eqz (local.get $n))
        (then (call $print_str (i32.const 164) (i32.const 3)) (call $print_nl) (return)))
      (call $print_str (i32.const 144) (i32.const 3))
      (local.set $i (i32.const 0))
      (loop $b
        (call $print_str (i32.const 148) (i32.const 1))
        (call $print_i64 (i64.load8_u offset=64 (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br_if $b (i32.lt_u (local.get $i) (local.get $n))))
      (call $print_nl)
      (br_if $out (i32.and (i32.eq (local.get $n) (i32.const 1))
                           (i32.eq (i32.load8_u (i32.const 64)) (i32.const 113))))
      (br $l)))
    (call $print_str (i32.const 152) (i32.const 8))
    (call $print_i64 (i64.extend_i32_s (call $key_pending)))
    (call $print_nl)
    (call $print_str (i32.const 160) (i32.const 3))
    (call $print_nl)))
