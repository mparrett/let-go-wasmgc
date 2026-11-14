# Roadmap

As of 2026-10-20:

- A linear-memory target beside WasmGC, specified in
  [docs/LINEAR-TARGET-SPEC.md](LINEAR-TARGET-SPEC.md), is started:
  tagged i32 values, a bump allocator and the wazero runner are in
  (`--target linear`, phase 8 of `checks/items.tsv`); the precise collector
  (phase 11) and an Asyncify build for browsers without JSPI are not.
- The module compiling at run time is built: the evaluator's second output
  (`rt/wasm/emit.lg`, D191), the backend carried as a program and
  self-compiling in the browser (`host/compile.html`, D206 to D212,
  phase 12), and a wasm binary encoder in plain lg (`rt/wasm/wasmbin.lg`,
  D190). [docs/SELF-HOST-SPEC.md](SELF-HOST-SPEC.md) is the spec.
- Still candidates, none started: the numeric tower's arithmetic over BigInt
  and Ratio (the values landed with D230); `go` blocks and channels, with a scheduler on JSPI; calls
  through var-table slots, so an evaluated redefinition reaches compiled
  callers; IR cached per namespace keyed by source hash.
