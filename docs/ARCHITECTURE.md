# Architecture

The map of the code: where each part lives and the decisions that shape
it. [READING-GUIDE.md](READING-GUIDE.md) then walks through the code in
reading order, stop by stop; [../DECISIONS.md](../DECISIONS.md) has the
full record behind the D-numbers cited here.

## Layout

- `src/` the compiler
  - `src/driver.lg` reads a program, evaluates its defns in-process so let-go's
    IR builder resolves vars, runs the IR pipeline per defn and writes one
    WAT module. Usage: `lg -source-paths src src/driver.lg <prog.lg> <out.wat>`.
  - `src/lower_wasm.lg` walks the structured IR control tree and emits WasmGC
    text: values, closures, the var table, exception handling, tail calls.
  - `src/lw_rt.lg` loads `rt/wasm/*.lg` in load order, indexes its types, defns
    and twins, and caches the compiled runtime library.
  - `src/lw_ext.lg` let-go code the backend compiles for natives the runtime has
    no form for (variadic uses, a regex engine, format, JSON).
  - `src/run.mjs` runs a module like `lg` runs a program: stdout, exit status,
    `error: <message>` on an uncaught exception.
  - `src/testshim.lg` the minimal `test` namespace for compiled test files.
- `rt/wasm/` the runtime, in let-go. A defn marked `^{:twin "core/first"}`
  claims the let-go native it replaces, and the backend routes calls to that
  native to the marked defn (D58). The files load as one runtime under native
  lg as well, with `intrinsics.lg` as a reference implementation of the wasm
  instructions, so the runtime is tested natively before it is compiled.
  `rt/wasm/README.md` has the load-order table, the value kind table and the
  declared differences from native.
- `host/` JS hosts (`lg-wasm-host.js`, `node-host.mjs`), the import ABI
  (`ABI.md`), the REPL, explorer, compile, xsofy and legmacs pages, their build
  scripts, and `wat-asm/`, the page-side assembler.
- `checks/` the oracle, the row table `items.tsv`, the gate runner and the
  check scripts.
- `corpus/` inputs and expected outputs for every check, one directory per
  area, plus review corpora and recorded results. `corpus/README.md` has
  the rules for adding to it and which layer tests what.
- `tools/` the native inventory and twin manifest (which natives a program
  reaches that the runtime does not provide).
- `DECISIONS.md` the design record. `FINDINGS.md` things learned that are
  not decisions. `docs/ITEM-LEDGER.md` the dated row table of work items.
  `docs/WORKFLOW.md` how issues, commits, reviews and gates are run.
  `docs/ROADMAP.md` where the backends might go next.
  `docs/EVAL-NATIVE-SPEC.md` a work order for running the evaluator outside
  wasm. `docs/history/` snapshots kept for the record.

## Design in brief

- **One module per program** (D10). Top-level defns are exported functions;
  other top-level forms run in order in an exported `_main`. An op, constant
  or control shape the backend does not handle is a named compile error, not
  a fallback; `corpus/refused` pins those.
- **Integers are hybrid** (D41): `ref.i31` when the value fits 31 bits
  signed, otherwise an `$Int` box. The form is canonical, so equality and
  hashing can rely on it. Booleans are two singleton globals (D22).
- **All runtime types sit in one rec group** (D25), so structs of the same
  shape stay distinct under `ref.test`. let-go `try`/`throw` lower to wasm
  exception handling; `wasm/trap` is kept for internal invariants.
- **Closures** are `$Fn` structs with one code ref per arity and an env
  field (D52); variadics and arities above 4 extend that layout (D83, D150).
- **Native quirks are reproduced, not fixed** (D16): the backend matches
  native lg's overflow, shift and error-text behaviour.
- **Host imports** are a small ABI (D88, `host/ABI.md`): print and write,
  sleep, clocks, getenv, and terminal key and size imports. Blocking imports
  (`sleep`, `read_key`) suspend through JSPI, which needs no COOP/COEP (D91).
- **The match relation** (D12, D13): `checks/oracle.sh` runs a program under
  native lg and through the backend and reports MATCH only when stdout is
  byte-identical, the exit class agrees, and on failure the normalised first
  error line agrees. `.expected` files are snapshots of native output,
  checked first so drift in lg is caught.
- **eval**: `rt/wasm/eval.lg` is a closure-compiling evaluator over reader
  data with let-go's special forms, its core macros as expanders and a core
  table (D160). When a program names `eval` or `*ns*`, `_main` switches to
  the program's namespace and installs a program table of its namespaces,
  vars and macros, so evaluated code resolves the program's own vars (D161).
  `LW_NO_EVAL=1` leaves out the evaluator and the table; modules that never
  reach `eval` are byte-identical either way (D163). `LW_PROGRAM_TABLE=1`
  installs the table without `eval`, for a program whose library inits
  resolve or intern their own vars (D204).
- **Compiling at run time** (docs/SELF-HOST-SPEC.md, stages 3a and 3b-i):
  `rt/wasm/emit.lg` is a second output of the evaluator's front end, a
  baseline emitter of wasm bytes. Built with `LW_EXPORT_RT=1
  LW_RUNTIME_COMPILE=1`, a module carries it and exports its whole runtime;
  `lw compile` turns one form's text into a module that declares the
  host's rec group byte for byte (so its structs are the host's) and
  imports what it calls from the running instance's exports, which is the
  whole import object. The compiled form shares the evaluator's vars,
  values and exceptions: an evaluated `try` catches what compiled code
  throws. Scalar forms, `def`, `fn` without captures and calls through any
  value are in; closures, `try` and collections built from expressions are
  the next stage (D191, D193; rows P10.1, P10.2). Without the flags the
  module's bytes do not change.
