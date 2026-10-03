# Reading guide

This is a curated walk through the backend, from the driver that turns a let-go program into one WebAssembly GC module, through the runtime and evaluator compiled into that module, to the hosts and the checks that hold it to native lg. Each stop says what the code does, why it has that shape, and which numbered decision in [DECISIONS.md](../DECISIONS.md) records the choice.

Every link pins commit e17fc75, so later changes to the tree will not move the lines they point at.

## 1. The driver

`src/driver.lg` runs under native lg. It reads the program, evaluates each top-level defn in-process so let-go's IR builder resolves self and mutual calls to real vars, and collects every other top-level form into the body of a synthetic `_main` defn (D10). It then analyses each defn and `_main` through let-go's IR pipeline inside one lowering session, lowers them, and writes a single WAT module. The lowering runs in a loop: a parameter stays an unboxed i64 only while every call passes an int, so when lowering reports a call that does not, that defn is re-analysed with boxed parameters until nothing new needs boxing. `analyze-program!` is the per-defn step; it also registers each signature before the next defn is analysed, so later callers are lowered against it.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/driver.lg#L860-L913

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/driver.lg#L233-L262

## 2. The type section

Every type the module uses is declared in one `(rec ...)` group, so two structs with the same field layout stay distinct under `ref.test` (D25). `rec-group` emits the runtime's own declarations in source order, then `$FnV` and `$FnX`, then the per-closure environment structs. A closure is a `$Fn` with one typed code ref per arity 0 to 4, an env field and a `$FnInfo` for error messages (D52); the runtime's declaration of `Fn` in `rt/wasm/seq.lg` is the source of truth, and the backend's view was reconciled to it (D76). Variadic fns are a `$FnV` subtype carrying the variadic code and its fixed-arg count, and fixed arities 5 to 20 live in `$FnX`, a subtype of `$FnV` (D83, D150). The `$Code<n>` func types are generated up to the largest arity any of these need.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/lower_wasm.lg#L3852-L3891

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/rt/wasm/seq.lg#L46-L48

## 3. Integer representation

An int is a `ref.i31` when it fits 31 bits signed and an `$Int` box otherwise (D41). The form is canonical: an in-range int is never an `$Int`, so equality and hashing can compare representations without normalising them. Where analysis proves a value is an int it stays an unboxed i64, and `coerce` converts between i64 and the boxed form at the edges. In program fns the box is emitted inline; in runtime helpers it stays a call to `$rt_box_int`, because inlining it there pushed the arithmetic helpers past V8's inlining budget and made fib slower (D41 records the measurement). `$rt_unbox_int` raises a catchable named error on a non-int rather than trapping on a bad cast.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/lower_wasm.lg#L183-L212

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/lower_wasm.lg#L3070-L3083

## 4. Exceptions

let-go `try` and `throw` lower to wasm exception handling with one tag, `$lgex`, whose payload is the thrown let-go value (D25, D31). Each region of a `try` (body, handler, finally) is lambda-lifted into its own wasm function that takes its captures as extra parameters. A handler is a `try_table` with `catch $lgex` around the body call; the caught value is reified and passed to the handler, whose class dispatch rethrows when nothing matches. A finally is a `catch_all_ref` that runs the finally code and then `throw_ref`s the original exception, so a raw runtime error keeps its uncaught message. Runtime errors are raised as `$Err` structs through the same throw (D68); `wasm/trap` is kept for internal invariants that must not be catchable.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/lower_wasm.lg#L2349-L2401

## 5. Tail calls and loop/recur

Native lg eliminates every tail call, including mutual and through fn values, so the backend must too: ten million tail calls may not grow the wasm stack. `tail-call-wat` turns a call in tail position into `return_call` when the callee is a known defn whose return kind matches, or `return_call` through `$rt_invoke<n>` for an unknown callee; anything else lowers as a normal call. `loop`/`recur` never become calls. The IR's structured control tree has `:loop`, `:continue` and `:break` nodes that `walk` lowers to a wasm `block`/`loop` pair with `br`, and fn-level `recur` (`:tail`) copies the new values into the parameters and branches back to the top of the function.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/lower_wasm.lg#L1884-L1918

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/lower_wasm.lg#L1995-L2027

## 6. Twin routing

The runtime replaces let-go's Go natives with let-go code. A runtime defn claims the native it implements with `^{:twin "core/first"}` (or a vector of names), and `src/lw_rt.lg` builds the table from native var to runtime var (D58). A twin also covers every other var bound to the same native fn value, which is why the table is also indexed by value: `string/trim` and `core/trim` share one. When the backend lowers a call, `rt-target` asks this table for the runtime defn that implements the callee, so a program's call to `first` becomes a direct call to `wasm.seq/first`. The twin itself is plain runtime-dialect code that reproduces native's behaviour and error text.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/lw_rt.lg#L164-L193

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/lower_wasm.lg#L3306-L3320

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/rt/wasm/seq.lg#L627-L633

## 7. The runtime's load order and value kinds

`rt/wasm/README.md` holds the two tables to keep open while reading the runtime. The load-order table lists the namespaces in the order they load, what each requires and what each owns; `src/lw_rt.lg` reads this table to decide what to load, so it is configuration as well as documentation. The kind table lists what `wasm.seq/kind` returns for each value: it is the single dispatch point for equality, hashing, printing and seq operations. `seq.lg` owns the value model and requires none of the collections, so there is no load cycle; maps and sets reach it through hooks installed at link time.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/rt/wasm/README.md#L10-L28

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/rt/wasm/README.md#L59-L90

## 8. Intrinsics as a reference implementation

The runtime is written against a small set of intrinsic vars in `rt/wasm/intrinsics.lg`, each tagged `^{:intrinsic true :wasm "..."}` with the wasm instruction it stands for. The backend recognises these by var identity and emits the instruction inline; `wasm/new` becomes `struct.new`, with the field count checked statically. Under native lg the same defns run as a reference implementation over object arrays, deliberately stricter than wasm where runtime code should never rely on wasm's behaviour. That is what lets the whole runtime load and run its test files under native lg (`checks/run-intrinsics-native.sh`) before any of it is compiled, so most runtime bugs show up as ordinary let-go failures.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/rt/wasm/intrinsics.lg#L170-L182

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/lower_wasm.lg#L1238-L1252

## 9. The evaluator

`rt/wasm/eval.lg` gives a compiled module a working `eval` (D160). `compile` turns a form into a let-go closure over a vector of local values, once, and `eval` calls it. `comp-seq` is the dispatch: a special form from the `specials` map, then a call of a local, then a macro expander, then an ordinary call. Core macros are ported as expanders that build the same forms native's macros do, so the nested `CompileError` chains come out identical. Unqualified symbols resolve in the order local, a cell of the current namespace, program vars, refers, cells interned into `let-go.core`, then the core table; qualified ones go through aliases. Locals are handled in `comp-sym`, the rest in `resolve-global`. The core table is a fn rather than a def so the backend links each twin it names.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/rt/wasm/eval.lg#L1027-L1036

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/rt/wasm/eval.lg#L1141-L1160

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/rt/wasm/eval.lg#L979-L994

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/rt/wasm/eval.lg#L162-L181

## 10. The program table

For evaluated code to see the program's own vars, the driver emits a program table (D161). `ns-table-entry!` builds one entry per program namespace with its aliases, refers, vars and macros. Each var is a `#'ns/name` stand-in whose getter is one shared closure over a per-namespace binary-search fn, so the table costs a name and a branch per var rather than a closure each; each `defmacro` is compiled as a hidden fn of its declared params. `registry-boot-forms` opens `_main` with an `in-ns` of the program's namespace when the program names `eval` or `*ns*`, then installs the table when `eval` is reached; a program that never reaches `eval` gets neither, so its module is unchanged (D163). `_main` itself is tagged with the program's namespace like every other defn, because a library loaded on demand during analysis can leave the compiler's `*ns*` elsewhere (D167).

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/driver.lg#L644-L685

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/driver.lg#L709-L725

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/src/driver.lg#L870-L874

## 11. The host ABI

A module talks to its host only through the imports in `host/ABI.md` (D88): output, sleep, a clock, getenv, arguments, and terminal key and size imports. Strings are GC byte arrays inside the module, and linear memory is only the copy area for crossing the boundary. The two blocking imports, `env.sleep` and `term.read_key`, are wrapped in `WebAssembly.Suspending` by `lg-wasm-host.js`, and `lw main` runs under `WebAssembly.promising`. The wasm stack parks on a Promise while the JS event loop keeps running, so keyboard input needs no SharedArrayBuffer and the page needs no cross-origin isolation headers (D91). Without JSPI the host refuses to block instead of letting a Promise be coerced to 0.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/host/ABI.md#L25-L48

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/host/lg-wasm-host.js#L165-L201

## 12. The match relation and the row table

`checks/oracle.sh` is the only definition of "matches" in the project (D12, D13). It runs a program under native lg and through the backend and reports MATCH only when stdout is byte-identical, both exits are zero or both non-zero, and on failure the normalised first error line agrees. `checks/wasm-run.sh` is the backend half: it runs the driver, assembles the WAT with wasm-tools and runs the module under node, behaving like `lg` on stdout and exit status. Every work item is a row of `checks/items.tsv` whose third column is the exact command whose exit 0 means done. Row P1.1 runs the oracle over the scalar corpus and a generated operator matrix of edge values; row P7.1 runs legmacs' REPL and let-go-mode tests under the module, and exits 2 when its test list does not exist yet, meaning the check itself is not built.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/checks/oracle.sh#L2-L14

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/checks/oracle.sh#L27-L38

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/checks/wasm-run.sh#L25-L42

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/checks/items.tsv#L4-L4

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/checks/items.tsv#L62-L62

## 13. The REPL demo

The browser REPL is an ordinary let-go program compiled by the same backend. `corpus/host/repl.lg` reads a line one key at a time with `term/read-key`, which suspends through JSPI between keys, reads every form on the line with `read-all-string`, evaluates them with the in-module `eval` and prints the last value with `prn`. Because it names `eval`, the driver gives it the evaluator and a program table (stop 10). `host/repl.html` echoes the input, sends each character to the module with `sendInput`, and offers an example picker; its snippets may use only names in the evaluator's core table.

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/corpus/host/repl.lg#L9-L29

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/host/repl.html#L48-L73

## 14. Where things are recorded

`DECISIONS.md` is the design record: one dated line per decision, D10 onward, and the code cites these numbers in its comments. D41 is a typical entry, recording a representation choice with the measurement behind it; D170 records how this repository is published. `STATUS.md` is the dated table of work items, each with its state and a note. `FINDINGS.md` lists native let-go behaviours met along the way that are not decisions, such as hashing and arithmetic quirks the backend reproduces rather than fixes (D16).

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/DECISIONS.md#L36-L36

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/DECISIONS.md#L165-L165

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/STATUS.md#L5-L20

https://github.com/mparrett/let-go-wasmgc/blob/e17fc750c435335c20fbd6a1a1724a5cec736cc4/FINDINGS.md#L1-L11
