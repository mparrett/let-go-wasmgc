;; wasmtime-adapter.wat — the host/ABI.md imports implemented on WASI
;; preview1, for running a lower-wasm module under the wasmtime CLI. No JS
;; there, so no JSPI: sleep and read_key simply block the thread.
;;
;; checks/browser-boot.sh merges it into the program with binaryen, once as
;; "env" and once (minus the "memory" export) as "term":
;;   wasm-merge --rename-export-conflicts prog.wasm main a.wasm env a-term.wasm term
;; The adapter works on the program's memory, which it imports as
;; main."lw mem" and re-exports as "memory" because WASI needs that name.
;;
;; Scratch: the low addresses are NOT free (the backend keeps an active data
;; segment at 0, "niltruefalse…", and print_str reads it from there), and
;; 32.. is where it copies strings for env.write. The adapter's iovecs,
;; digits and poll structs therefore live in the top 128 bytes of memory; if
;; the string being written reaches into them, the adapter grows memory by a
;; page first. The program checks memory.size before every copy, so a grow
;; here only gives it room.
(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "main" "lw mem" (memory 1))
  (export "memory" (memory 0))
  ;; base of a 128-byte scratch area that does not overlap [0, live_end)
  (func $scratch (param $live_end i32) (result i32) (local $base i32)
    (local.set $base (i32.sub (i32.mul (memory.size) (i32.const 65536)) (i32.const 128)))
    (if (i32.gt_u (local.get $live_end) (local.get $base))
      (then (drop (memory.grow (i32.const 1)))
            (local.set $base (i32.sub (i32.mul (memory.size) (i32.const 65536)) (i32.const 128)))))
    (local.get $base))
  (func $out (param $fd i32) (param $ptr i32) (param $len i32) (local $s i32)
    (local.set $s (call $scratch (i32.add (local.get $ptr) (local.get $len))))
    (i32.store (local.get $s) (local.get $ptr))
    (i32.store offset=4 (local.get $s) (local.get $len))
    (drop (call $fd_write (local.get $fd) (local.get $s) (i32.const 1) (i32.add (local.get $s) (i32.const 8)))))
  (func (export "write") (param $fd i32) (param $ptr i32) (param $len i32) (result i32)
    (call $out (local.get $fd) (local.get $ptr) (local.get $len))
    (local.get $len))
  (func (export "print_str") (param $ptr i32) (param $len i32)
    (call $out (i32.const 1) (local.get $ptr) (local.get $len)))
  (func (export "print_nl") (local $s i32)
    (local.set $s (call $scratch (i32.const 0)))
    (i32.store8 offset=64 (local.get $s) (i32.const 10))
    (call $out (i32.const 1) (i32.add (local.get $s) (i32.const 64)) (i32.const 1)))
  ;; digits right-aligned ending at s+96 (i64 min is 20 characters)
  (func (export "print_i64") (param $v i64) (local $s i32) (local $end i32) (local $p i32) (local $d i64) (local $neg i32)
    (local.set $s (call $scratch (i32.const 0)))
    (local.set $end (i32.add (local.get $s) (i32.const 96)))
    (local.set $p (local.get $end))
    (local.set $neg (i64.lt_s (local.get $v) (i64.const 0)))
    (loop $l
      (local.set $d (i64.rem_s (local.get $v) (i64.const 10)))
      (if (local.get $neg) (then (local.set $d (i64.sub (i64.const 0) (local.get $d)))))
      (local.set $p (i32.sub (local.get $p) (i32.const 1)))
      (i32.store8 (local.get $p) (i32.add (i32.const 48) (i32.wrap_i64 (local.get $d))))
      (local.set $v (i64.div_s (local.get $v) (i64.const 10)))
      (br_if $l (i64.ne (local.get $v) (i64.const 0))))
    (if (local.get $neg) (then
      (local.set $p (i32.sub (local.get $p) (i32.const 1)))
      (i32.store8 (local.get $p) (i32.const 45))))
    (call $out (i32.const 1) (local.get $p) (i32.sub (local.get $end) (local.get $p))))
  (func (export "nanotime") (result i64) (local $s i32)
    (local.set $s (call $scratch (i32.const 0)))
    (drop (call $clock_time_get (i32.const 1) (i64.const 0) (local.get $s)))
    (i64.load (local.get $s)))
  ;; one relative clock subscription: subscription 48 bytes @s, event 32
  ;; bytes @s+48, nevents @s+80
  (func (export "sleep") (param $ms i64) (local $s i32)
    (if (i64.le_s (local.get $ms) (i64.const 0)) (then (return)))
    (local.set $s (call $scratch (i32.const 0)))
    (memory.fill (local.get $s) (i32.const 0) (i32.const 128))
    (i32.store offset=16 (local.get $s) (i32.const 1))                 ;; tag 0 = clock; id 1 = monotonic
    (i64.store offset=24 (local.get $s) (i64.mul (local.get $ms) (i64.const 1000000)))
    (drop (call $poll_oneoff (local.get $s) (i32.add (local.get $s) (i32.const 48)) (i32.const 1)
                             (i32.add (local.get $s) (i32.const 80)))))
  ;; one stdin byte per key; 0 at EOF (read-key -> nil)
  (func (export "read_key") (param $buf i32) (param $cap i32) (result i32) (local $s i32)
    (if (i32.eqz (local.get $cap)) (then (return (i32.const 0))))
    (local.set $s (call $scratch (i32.add (local.get $buf) (local.get $cap))))
    (i32.store (local.get $s) (local.get $buf))
    (i32.store offset=4 (local.get $s) (i32.const 1))
    (i32.store offset=8 (local.get $s) (i32.const 0))
    (drop (call $fd_read (i32.const 0) (local.get $s) (i32.const 1) (i32.add (local.get $s) (i32.const 8))))
    (i32.load offset=8 (local.get $s)))
  ;; a non-blocking peek would need poll_oneoff on fd 0; not done here,
  ;; so this host always reports "nothing pending"
  (func (export "key_pending") (result i32) (i32.const 0))
  (func (export "size") (result i32 i32) (i32.const 80) (i32.const 24)))
