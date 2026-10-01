# wasm.intrinsics (P2.1, native half, 2026-09-30)

The var set the wasm runtime is written against (plan D4). Source of truth is
the metadata on each `^:intrinsic` defn in `intrinsics.lg` (`:wasm`, `:type`);
`intrinsics_test.lg`'s `intrinsic-coverage` test fails if an intrinsic lacks
either key or is not exercised by that file. Check: `checks/run-intrinsics-native.sh`.

**Types.** Every operand and result is an lg typeinfer type: `:int` = i64,
`:float` = f64, `:bool` = i32, `:any` = `(ref null eq)`. i32 and i8 exist only
as field/element storage; the backend inserts `i32.wrap_i64` /
`i64.extend_i32_*` inside the intrinsic's expansion, so runtime lg never sees
an i32. `decl` is a var defined by a declaration form, resolved statically.

**Declarations** (top-level `def`s the backend reads as a data table, emitted
as ONE `(rec ...)` group so same-shaped types stay distinct for `ref.test`):
`(defstruct Name [t ...])` with `t` in `:i64 :f64 :i32 :ref :funcref` or
`[:mut t]`; `(defarray Name t)` (elements always mutable); `(deffunc Name [t ...] t)`;
built-in `Bytes` = `(array (mut i8))`.

Used by: **P** = `pvec.lg`, **H** = HAMT (P2.4), **C** = closures/arity dispatch (P1.3),
**V** = value model, hash, strings (P2.2/P2.6), **IO** = host boundary. All are used by the test file.

| name | arity | wasm | type | used by |
|---|---|---|---|---|
| `new` | 1–8 | struct.new | [decl fields…] → :any | P H C V |
| `get` | 3 | ref.cast; struct.get (i32: extend_s) | [decl const :any] → field | P H C V |
| `set!` | 4 | ref.cast; struct.set (mut fields only) | [decl const :any T] → nil | H (transient edit), V (hash cache) |
| `is?` | 2 | ref.test | [decl :any] → :bool | H (node kind), V (type dispatch) |
| `as` | 2 | ref.cast (non-null) | [decl :any] → :any | H V |
| `array-new` | 3 | array.new | [decl :int T] → :any | P H C |
| `aget` / `aset!` | 3 / 4 | array.get / array.set | [decl :any :int (T)] | P H C |
| `alen` | 1 | array.len; extend_u | [:any] → :int | P H V |
| `array-copy` | 6 | array.copy (memmove) | [decl dst di src si n] → nil | P H V |
| `ref-eq` | 2 | ref.eq | [:any :any] → :bool | H (identity fast path, transient owner) V |
| `null` / `null?` | 0 / 1 | ref.null none / ref.is_null | | P H |
| `i31` / `i31?` / `i31-get` | 1 | ref.i31 / ref.test i31 / i31.get_s | | V (D2 hybrid box), P test |
| `i64-add` `-sub` `-mul` | 2 | i64.add/sub/mul (wrap) | [:int :int] → :int | V (murmur3, hash mixing) |
| `i64-shl` `-shr-s` `-shr-u` | 2 | i64.shl/shr_s/shr_u (count mod 64) | [:int :int] → :int | H (bitpos) V |
| `i64-lt-u` | 2 | i64.lt_u | → :bool | V (uint32 hash compare) |
| `i64-clz` `-ctz` `-popcnt` | 1 | i64.clz/ctz/popcnt | → :int | H (popcnt = bitmap index) |
| `i32-wrap` | 1 | extend_i32_s(wrap_i64) | → :int | V (32-bit murmur3 in i64) |
| `i64-extend-i32-u` | 1 | extend_i32_u(wrap_i64) | → :int | H V (hash as uint32) |
| `i64-to-f64` / `f64-to-i64` | 1 | f64.convert_i64_s / i64.trunc_f64_s (traps) | | V (`double`, `long`) |
| `bytes-new` `bget` `bset!` | 1/2/3 | array.new_default / get_u / set ($Bytes) | | V (strings, D5) IO |
| `bytes-of-string` | 1 | array.new_data (literal only) | [:string] → :any | V IO |
| `string-of-bytes` | 1 | none (identity) | [:any] → :string | reference/test boundary only |
| `host-write` `host-sleep` `host-nanotime` `host-getenv` | 2/1/0/1 | call $env.* | | IO (D6, D11's `env.write`) |
| `trap` | 1 | unreachable | [:string] → :bottom | P V |
| `funcref` / `call-ref` | 2 / 2–7 | ref.func / call_ref $Sig (7 = `$Code4`: closure + 4 args, P2.7) | | C |

42 intrinsics, 3 declaration macros, 1 built-in type, as of 2026-09-30.
`new` gained its 7-field arity on 2026-10-01 for D52's `$Fn`.

**Reference semantics.** Wrapping arithmetic, shift counts mod 64, packed-i8
truncation in `bset!`, and memmove `array-copy` match wasm exactly (measured on
lg 4e769212: `unchecked-add` wraps; lg's own shifts follow Go, so the reference
masks the count; `(long ##NaN)` is 0 and `(long 1e19)` saturates, so
`f64-to-i64` checks the trap cases itself). The reference is *stricter* than
wasm where wasm is silent and a correct runtime never relies on it: an
out-of-range `i31` traps (wasm drops the top bit), an index ≥ 2^32 traps (wasm
would wrap it to i32 and may land in bounds), a raw lg value in a `:ref` slot
or an out-of-range value in an `:i32` slot throws. Host calls are
deterministic: a virtual clock advanced only by `host-sleep`, env from
`*host-env*`.

**Not intrinsics, on purpose.** No `wasm/throw`/`wasm/try`: the runtime throws
catchable errors with lg's own `try` and `core/throw` (P1.2's `:try`) once
`ex-info` exists (P2.7); internal invariants use `trap`, which is uncatchable
in wasm too. No `blen` (`alen` takes `Bytes`) and no `i64-extend-i32-s` (it is
`i32-wrap`).

**HAMT (P2.4) needs, and has:** BitmapIndexedNode `[:i64 bitmap, [:mut :ref] edit, :ref arr]`,
ArrayNode `[[:mut :i64] cnt, [:mut :ref] edit, :ref arr]`, HashCollisionNode
`[:i64 hash, [:mut :i64] cnt, [:mut :ref] edit, :ref arr]` (`defstruct`/`new`/`get`/`set!`);
node kind dispatch (`is?`/`as`); `bitpos = 1 << ((h >>> shift) & 31)` (IR shifts or `i64-shl`/`i64-shr-u`);
`index = popcnt(bitmap & (bit - 1))` (`i64-popcnt`); hash as uint32 (`i64-extend-i32-u`);
insert/remove by allocate-and-copy-twice (`array-new`, `array-copy`); key compare via
the runtime's `=` with a `ref-eq` fast path; transient ownership by `ref-eq` on the edit token.
Covered. **Gap for P2.2:** hashing a float needs its IEEE bits (`i64.reinterpret_f64`),
which this set lacks and which native lg offers no non-interop way to compute; add
`f64-bits` there, with its reference implementation, when P2.2 needs it. Until then
`wasm.seq/float-bits` computes the bits with float arithmetic (STR.md, Floats).
