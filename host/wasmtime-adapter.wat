;; wasmtime-adapter.wat — the host/ABI.md imports implemented on WASI
;; preview1, for running a lower-wasm module under the wasmtime CLI. No JS
;; there, so no JSPI: sleep and read_key simply block the thread (D232).
;;
;; checks/wasmtime-run.sh merges it into the program with binaryen, once as
;; "env" and once (minus the "memory" and "_start" exports) as "term":
;;   wasm-merge --rename-export-conflicts prog.wasm main a.wasm env a-term.wasm term
;; The adapter works on the program's memory, which it imports as
;; main."lw mem" and re-exports as "memory" because WASI needs that name.
;; Its "_start" calls main."lw main", so wasmtime runs the merged module as
;; a WASI command: the arguments after the module are the program's os/args
;; (`--argv0` supplies the lg path, as node's hosts do) and nothing is
;; printed after the program's output.
;;
;; Scratch: the low addresses are NOT free (the backend keeps an active data
;; segment at 0, "niltruefalse…", and print_str reads it from there), and
;; 32.. is where it copies strings for env.write. The adapter's iovecs,
;; digits and poll structs therefore live in the top 128 bytes of memory; if
;; the string being written reaches into them, the adapter grows memory by a
;; page first. The program checks memory.size before every copy, so a grow
;; here only gives it room. The environment and argument blocks WASI hands
;; over (getenv, argc, arg) are larger and of unknown size, so $reserve
;; places them just below those 128 bytes, growing memory as needed.
(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close" (func $fd_close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_filestat_get" (func $fd_filestat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_open" (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_sizes_get" (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_get" (func $environ_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_sizes_get" (func $args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_get" (func $args_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "main" "lw mem" (memory 1))
  (import "main" "lw main" (func $lw_main (result anyref)))
  (import "main" "lw lgex" (tag $lgex (param eqref)))
  (import "main" "lw report" (func $lw_report (param eqref)))
  (export "memory" (memory 0))
  ;; the fd print_* write to: 1, or 2 while an uncaught exception is formatted
  (global $outfd (mut i32) (i32.const 1))
  ;; The WASI command entry: the program's top-level forms, result dropped.
  ;; An uncaught lg exception is reported as src/run.mjs does (ABI.md,
  ;; Errors): `error: ` and the module's own formatting of the value on fd 2,
  ;; a newline, exit 1. A wasm trap still ends in wasmtime's own report; a
  ;; `wasm/trap` has printed its message by then.
  (export "_start" (func $start))
  (func $start (local $v eqref) (local $s i32)
    (block $caught (result eqref)
      (try_table (catch $lgex $caught) (drop (call $lw_main)))
      (return))
    (local.set $v)
    (global.set $outfd (i32.const 2))
    (local.set $s (call $scratch (i32.const 0)))
    (i64.store offset=64 (local.get $s) (i64.const 0x203a726f727265))   ;; "error: " little-endian
    (call $out (i32.const 2) (i32.add (local.get $s) (i32.const 64)) (i32.const 7))
    (call $lw_report (local.get $v))
    (call $print_nl)
    (call $proc_exit (i32.const 1)))
  ;; base of a 128-byte scratch area that does not overlap [0, live_end)
  (func $scratch (param $live_end i32) (result i32) (local $base i32)
    (local.set $base (i32.sub (i32.mul (memory.size) (i32.const 65536)) (i32.const 128)))
    (if (i32.gt_u (local.get $live_end) (local.get $base))
      (then (drop (memory.grow (i32.const 1)))
            (local.set $base (i32.sub (i32.mul (memory.size) (i32.const 65536)) (i32.const 128)))))
    (local.get $base))
  ;; base of a $need-byte area below the scratch that does not overlap
  ;; [0, live_end): grows memory by as many pages as that takes. The base is
  ;; 8-aligned (WASI rejects an unaligned pointer array).
  (func $reserve (param $live_end i32) (param $need i32) (result i32) (local $base i32) (local $want i32)
    (local.set $need (i32.and (i32.add (local.get $need) (i32.const 7)) (i32.const -8)))
    (local.set $want (i32.add (local.get $live_end) (i32.add (local.get $need) (i32.const 128))))
    (if (i32.gt_u (local.get $want) (i32.mul (memory.size) (i32.const 65536)))
      (then (drop (memory.grow (i32.add (i32.const 1)
                    (i32.div_u (i32.sub (local.get $want) (i32.mul (memory.size) (i32.const 65536))) (i32.const 65536)))))))
    (i32.sub (i32.sub (i32.mul (memory.size) (i32.const 65536)) (i32.const 128)) (local.get $need)))
  (func $out (param $fd i32) (param $ptr i32) (param $len i32) (local $s i32)
    (local.set $s (call $scratch (i32.add (local.get $ptr) (local.get $len))))
    (i32.store (local.get $s) (local.get $ptr))
    (i32.store offset=4 (local.get $s) (local.get $len))
    (drop (call $fd_write (local.get $fd) (local.get $s) (i32.const 1) (i32.add (local.get $s) (i32.const 8)))))
  (func (export "write") (param $fd i32) (param $ptr i32) (param $len i32) (result i32)
    (call $out (local.get $fd) (local.get $ptr) (local.get $len))
    (local.get $len))
  (func (export "print_str") (param $ptr i32) (param $len i32)
    (call $out (global.get $outfd) (local.get $ptr) (local.get $len)))
  (func $print_nl (export "print_nl") (local $s i32)
    (local.set $s (call $scratch (i32.const 0)))
    (i32.store8 offset=64 (local.get $s) (i32.const 10))
    (call $out (global.get $outfd) (i32.add (local.get $s) (i32.const 64)) (i32.const 1)))
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
    (call $out (global.get $outfd) (local.get $p) (i32.sub (local.get $end) (local.get $p))))
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
  ;; ---- getenv's copy contract: the value's byte length, copied only when
  ;; it fits in cap (ABI.md)
  (func $copy_out (param $src i32) (param $len i32) (param $buf i32) (param $cap i32) (result i32)
    (if (i32.le_u (local.get $len) (local.get $cap))
      (then (memory.copy (local.get $buf) (local.get $src) (local.get $len))))
    (local.get $len))
  (func $strlen (param $p i32) (result i32) (local $n i32)
    (block $done (loop $l
      (br_if $done (i32.eqz (i32.load8_u (i32.add (local.get $p) (local.get $n)))))
      (local.set $n (i32.add (local.get $n) (i32.const 1)))
      (br $l)))
    (local.get $n))
  ;; 1 when [p, p+n) equals [q, q+n)
  (func $memeq (param $p i32) (param $q i32) (param $n i32) (result i32) (local $i i32)
    (block $no (loop $l
      (br_if $no (i32.ge_u (local.get $i) (local.get $n)))
      (if (i32.ne (i32.load8_u (i32.add (local.get $p) (local.get $i))) (i32.load8_u (i32.add (local.get $q) (local.get $i))))
        (then (return (i32.const 0))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (i32.const 1))
  ;; os/getenv over WASI's environ (wasmtime passes the process's with
  ;; -S inherit-env=y): -1 when no "NAME=" entry exists
  (func (export "getenv") (param $nptr i32) (param $nlen i32) (param $buf i32) (param $cap i32) (result i32)
    (local $s i32) (local $count i32) (local $size i32) (local $r i32) (local $i i32) (local $p i32) (local $live i32)
    (local.set $live (i32.add (local.get $nptr) (local.get $nlen)))
    (if (i32.gt_u (i32.add (local.get $buf) (local.get $cap)) (local.get $live))
      (then (local.set $live (i32.add (local.get $buf) (local.get $cap)))))
    (local.set $s (call $scratch (local.get $live)))
    (drop (call $environ_sizes_get (local.get $s) (i32.add (local.get $s) (i32.const 4))))
    (local.set $count (i32.load (local.get $s)))
    (local.set $size (i32.load offset=4 (local.get $s)))
    ;; count pointers, then the NUL-terminated "NAME=value" strings
    (local.set $r (call $reserve (local.get $live) (i32.add (i32.mul (local.get $count) (i32.const 4)) (local.get $size))))
    (drop (call $environ_get (local.get $r) (i32.add (local.get $r) (i32.mul (local.get $count) (i32.const 4)))))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (local.get $count)))
      (local.set $p (i32.load (i32.add (local.get $r) (i32.mul (local.get $i) (i32.const 4)))))
      (if (i32.and (call $memeq (local.get $p) (local.get $nptr) (local.get $nlen))
                   (i32.eq (i32.load8_u (i32.add (local.get $p) (local.get $nlen))) (i32.const 61)))  ;; '='
        (then
          (local.set $p (i32.add (local.get $p) (i32.add (local.get $nlen) (i32.const 1))))
          (return (call $copy_out (local.get $p) (call $strlen (local.get $p)) (local.get $buf) (local.get $cap)))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (i32.const -1))
  ;; os/args (D115): WASI's argv as wasmtime passes it, argv[0] from --argv0
  (func (export "argc") (result i32) (local $s i32)
    (local.set $s (call $scratch (i32.const 0)))
    (drop (call $args_sizes_get (local.get $s) (i32.add (local.get $s) (i32.const 4))))
    (i32.load (local.get $s)))
  ;; argument i under getenv's contract; past the end it is "" (length 0),
  ;; as the JS hosts answer
  (func (export "arg") (param $i i32) (param $buf i32) (param $cap i32) (result i32)
    (local $s i32) (local $count i32) (local $size i32) (local $r i32) (local $p i32)
    (local.set $s (call $scratch (i32.add (local.get $buf) (local.get $cap))))
    (drop (call $args_sizes_get (local.get $s) (i32.add (local.get $s) (i32.const 4))))
    (local.set $count (i32.load (local.get $s)))
    (local.set $size (i32.load offset=4 (local.get $s)))
    (if (i32.ge_u (local.get $i) (local.get $count)) (then (return (i32.const 0))))
    (local.set $r (call $reserve (i32.add (local.get $buf) (local.get $cap))
                                 (i32.add (i32.mul (local.get $count) (i32.const 4)) (local.get $size))))
    (drop (call $args_get (local.get $r) (i32.add (local.get $r) (i32.mul (local.get $count) (i32.const 4)))))
    (local.set $p (i32.load (i32.add (local.get $r) (i32.mul (local.get $i) (i32.const 4)))))
    (call $copy_out (local.get $p) (call $strlen (local.get $p)) (local.get $buf) (local.get $cap)))
  ;; slurp (D208): the file's bytes under getenv's contract, read through
  ;; the first preopen (fd 3: `--dir .`, so paths are relative to the cwd as
  ;; under native lg); -1 when the open fails or the path is not a regular
  ;; file, which is what the node hosts answer for a missing file.
  ;; filestat: filetype u8 at +16, size u64 at +32.
  (func (export "read_file") (param $pptr i32) (param $plen i32) (param $buf i32) (param $cap i32) (result i32)
    (local $s i32) (local $fd i32) (local $size i32) (local $off i32) (local $n i32) (local $live i32)
    (local.set $live (i32.add (local.get $pptr) (local.get $plen)))
    (if (i32.gt_u (i32.add (local.get $buf) (local.get $cap)) (local.get $live))
      (then (local.set $live (i32.add (local.get $buf) (local.get $cap)))))
    (local.set $s (call $scratch (local.get $live)))
    ;; dirflags 1 = follow symlinks; rights fd_read (bit 1) and fd_filestat_get (bit 21)
    (if (i32.ne (i32.const 0) (call $path_open (i32.const 3) (i32.const 1) (local.get $pptr) (local.get $plen)
                                   (i32.const 0) (i64.const 0x200002) (i64.const 0) (i32.const 0) (local.get $s)))
      (then (return (i32.const -1))))
    (local.set $fd (i32.load (local.get $s)))
    (if (i32.ne (i32.const 0) (call $fd_filestat_get (local.get $fd) (i32.add (local.get $s) (i32.const 8))))
      (then (drop (call $fd_close (local.get $fd))) (return (i32.const -1))))
    (if (i32.ne (i32.load8_u offset=24 (local.get $s)) (i32.const 4))   ;; 4 = regular_file
      (then (drop (call $fd_close (local.get $fd))) (return (i32.const -1))))
    (local.set $size (i32.wrap_i64 (i64.load offset=40 (local.get $s))))
    (if (i32.gt_u (local.get $size) (local.get $cap))
      (then (drop (call $fd_close (local.get $fd))) (return (local.get $size))))
    ;; iovec @s+80, nread @s+88
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $off) (local.get $size)))
      (i32.store offset=80 (local.get $s) (i32.add (local.get $buf) (local.get $off)))
      (i32.store offset=84 (local.get $s) (i32.sub (local.get $size) (local.get $off)))
      (br_if $done (i32.ne (i32.const 0) (call $fd_read (local.get $fd) (i32.add (local.get $s) (i32.const 80)) (i32.const 1)
                                                      (i32.add (local.get $s) (i32.const 88)))))
      (local.set $n (i32.load offset=88 (local.get $s)))
      (br_if $done (i32.eqz (local.get $n)))
      (local.set $off (i32.add (local.get $off) (local.get $n)))
      (br $l)))
    (drop (call $fd_close (local.get $fd)))
    (local.get $off))
  ;; js/emit and js/url-param (D100): no page here, so as node's hosts
  ;; answer, the event is dropped and every parameter is absent (-1 -> nil)
  (func (export "emit") (param $nptr i32) (param $nlen i32) (param $dptr i32) (param $dlen i32))
  (func (export "url_param") (param $nptr i32) (param $nlen i32) (param $buf i32) (param $cap i32) (result i32)
    (i32.const -1))
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
