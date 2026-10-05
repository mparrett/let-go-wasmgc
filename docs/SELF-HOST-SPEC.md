# Spec: compiling at run time, a baseline compiler as the evaluator's second output

Written 2026-10-03. A work order for an agent or a person new to this code.
Read `README.md`, `docs/READING-GUIDE.md` (stops 1, 2, 3, 9, 10, 12), then
this file. It describes a second compiler that lives inside the emitted
module and compiles let-go forms while the program runs. It does not change
how modules are built on the host, and it does not touch the WasmGC target's
output unless a flag asks for it.

## Why, and why not the existing compiler

A compiled program can `eval` today through `rt/wasm/eval.lg`, a closure
compiler: it turns a form into a let-go closure once and runs that. It is
fast enough for a REPL and for legmacs's `C-x C-e`, and it is slower than
compiled code by the usual interpreter margin. The question is how a module
compiles code it did not have at build time.

The obvious answer, running the optimizing compiler inside the module, was
costed in the compiler census (2026-10-03) and rejected for this purpose:

- It is a toolchain, not a function: the IR builder and passes (about 8k
  lines of unconstrained lg), typeinfer running twice per function, and the
  backend itself, all compiled into every module. legmacs is 166 KB brotli
  with the evaluator; this would multiply it.
- Its front half depends on Go natives, macroexpansion above all. The
  census reached 227 natives from the compiler, 27 without a twin, and the
  real cost is macroexpansion fidelity and records the evaluator lacks. The
  expanders would have to be ported in any case, which the evaluator has
  already done for the core macros.
- Speed: the host driver takes about 232 s wall for legmacs natively
  (2026-10-02), a third of it typeinfer. At wasm speed a `defn`
  redefinition would take seconds.

What it would buy is one set of semantics. That is the risk of a second
compiler, and the oracle below is how the risk is bounded.

The answer this spec takes: the evaluator's front end already does the
semantics-bearing work, reading, macroexpansion with the ported expanders,
resolution through the program table, destructuring and arities. A baseline
emitter walks the same resolved forms and produces wasm bytes with
everything boxed, no inference, no loop-invariant motion. Roughly 2k lines
of runtime-dialect lg plus a binary encoder, running in milliseconds. The
optimizing compiler stays on the host and keeps producing shipped modules.
This is a tier, not a replacement.

## What exists that this builds on

- `rt/wasm/eval.lg`: `compile` (line ~1067) turns a form into a closure;
  `comp-seq` (~1027) is the dispatch (special form, local call, macro,
  ordinary call); `comp-sym` (~979) and `resolve-global` (~162) implement
  the resolution order local, cell, program vars, refers, core cells, core
  table, aliases; `specials` (~481) is the special-form map; the core table
  starts near line 1141. D160.
- The program table (`src/driver.lg`, `ns-table-entry!` ~644,
  `registry-boot-forms` ~709; D161): one entry per program namespace with
  aliases, refers, vars (a `#'ns/name` stand-in whose getter is a shared
  closure over a per-namespace binary search) and macros compiled as hidden
  fns. Evaluated code resolves the program's own vars through it.
- The value representation (D41, D22, D52, D150) and the single rec group
  (D25): every runtime type is declared once, in order, in one `(rec ...)`.
  WasmGC types are iso-recursive, so two modules share a type only when the
  whole rec group is identical. This decides the linking design below.
- Module exports today: `lw main`, `lw mem`, `lw report`, `lw lgex`
  (`src/lower_wasm.lg` ~2537, ~3064). Runtime functions are not exported.
- Native lg is the oracle (`checks/oracle.sh`, D12/D13), and
  `checks/run-corpus.sh` runs it over a directory. For this work the
  relation gains a second leg: compiled-at-run-time output must equal
  `eval`'s output, which must equal native's.

## Design decisions (made; a deviation goes in DECISIONS.md with the next number)

1. **Input is the evaluator's resolved form, not source text.** The
   baseline emitter consumes what `compile` would consume after
   macroexpansion and resolution, so the two share one meaning of every
   symbol. No second reader, no second expander, no second resolution.
2. **Everything boxed.** Parameters, locals and results are `(ref null eq)`;
   ints are the D41 hybrid produced by the runtime's box helpers; arithmetic
   and comparison call the runtime's boxed helpers (the same ones the host
   backend uses in non-inferred code). No type inference in milestone 1 of
   this spec; a later milestone may add fixnum fast paths behind the same
   oracle.
3. **Binary output, no WAT.** The emitter produces bytes directly: a small
   encoder for the sections it uses (type, import, function, export, code,
   and later element). It never prints text, because there is no parser in
   the module. The encoder is the one piece the host driver may later adopt
   too (ROUND4 item 1), but that is a separate change.
4. **Types by copying the rec group.** The emitted module declares the
   same rec group as the host module, byte for byte, so its structs are the
   host's structs. The host build writes the rec group's binary type
   section into the module as a data constant (behind the same flag as the
   exports below); the emitter copies it and appends its own function types
   after the group. Until that constant exists, stage 3a below uses a
   private minimal group and no runtime types cross the boundary.
5. **Linking by import.** Compiled code calls runtime functions and reads
   program vars through imports; the host instantiates the compiled bytes
   with an import object built from the running instance's exports. That
   needs the host module to export its runtime functions and var slots,
   which it does only when built with `LW_EXPORT_RT=1`. With the flag off,
   the host module is byte-identical to today (acceptance item 1).
6. **Vars, not patching.** A compiled fn is installed by writing it into the
   program var it defines, exactly as `eval` of a `defn` does today. Making
   already-compiled callers see a redefinition (calls through var-table
   slots) is out of this milestone; the oracle therefore compares behaviour
   reached through the var, not through earlier direct calls. It is not
   optional in the long run: let-go's stated semantics are that compiled code
   observes var redefinition unless the var is `^:const` or `^:inline`, with
   `^:dynamic`, `^:redef` and `with-redefs` always indirect, so var slots are
   the first item after stage 4. Likewise, if any of this ever faces
   upstream, it must be presented as a tier of the one compiler, under its
   `lg.compiler.*` layout, because a second permanent compiler architecture
   beside `ir.*` was explicitly rejected there.
7. **Opt-in, additive.** New runtime file `rt/wasm/emit.lg` (load order
   after `eval.lg` in `rt/wasm/README.md`'s table), loaded only when
   `LW_RUNTIME_COMPILE=1`; `eval.lg` is not modified except for one hook
   point that is a no-op without the flag. The default build's bytes do not
   change (acceptance item 1).
8. **No edits to `src/lower_wasm.lg` or `src/driver.lg` while the
   linear-target milestone 1 pull request is open**, except the two flag
   points named in stage 3b, and those only after that PR merges or by
   explicit agreement with its author. Stage 3a needs none.

## Stages, each with its own oracle

The subset ladder follows the corpus's own order, so every rung has an
existing directory of programs and expected outputs.

- **3a. Pure scalar, standalone (startable now).** Forms over ints, floats,
  booleans and nil: `let`, `if`, `do`, `loop`/`recur`, `fn` with fixed
  arities, arithmetic and comparison. The emitter produces a standalone
  module with a private minimal rec group (`$Int`, `$Float`, `$Bool`), no
  imports, one export per compiled fn. Oracle: a node check instantiates
  the bytes, calls the export with boxed arguments, and compares with
  `eval` of the same form over the same arguments, over `corpus/scalar/`
  and the programs of `corpus/opmatrix/` and `corpus/typed/` that fit the
  subset (the check lists which it skipped and why). Done when every fitting
  program agrees on every row of the operator matrix, including the D16
  quirks and the named errors (division by zero, overflow where native
  overflows).
  Status (2026-10-05): done, D191, row P10.1.
- **3b. Calls into the runtime and the program (needs the two flags).**
  `LW_EXPORT_RT=1` exports every runtime function with a stable name and
  every program var slot; the rec-group constant from decision 4 is emitted
  under the same flag. The emitter now imports what it calls: seq and
  collection functions, string functions, the boxed arithmetic helpers,
  program vars. Oracle: `checks/run-corpus.sh` over `corpus/control/`,
  `corpus/closure/`, `corpus/seqs/`, `corpus/edn/`, through a runner that
  evaluates each program's top level with the compiled path instead of
  `eval` (a `compile-form` fn in the module that returns bytes; the host
  instantiates and runs them). Done when those directories MATCH native and
  the default build's bytes are unchanged.
  Status (2026-10-05): first half (3b-i) done, D193, row P10.2: both
  flags, the module's own `lw compile`, linking over the scalar subset;
  coverage of those four directories is 3b-ii.
- **4. Linking inside the module.** The REPL and legmacs call
  `(compile-fn 'sym)`; the module itself asks the host to instantiate the
  bytes (one host import, `env.instantiate(ptr, len) -> i32 handle`, since
  wasm cannot instantiate wasm) and installs the resulting function value
  into the var. Oracle: the REPL `(compile ..)` agrees with `(eval ..)` on
  every example in `host/repl.html`'s picker and on `corpus/eval/`; legmacs
  `C-x C-e` on a `defn` followed by a call gives the same result either way.
  Status (2026-10-05): not started; node's side of the host import exists
  (`linkCompiled` in host/node-host.mjs, D193).
- **5. Policy and measurement.** When to compile: a `defn` evaluated twice,
  or legmacs's eval-buffer by default. Measure on fib(25) and on legmacs's
  eval tests: interpreted, baseline-compiled, host-compiled, with dates.
  Decide the default from the numbers and record it.
  Status (2026-10-05): not started.

Stage 1 of ROUND4's list, the binary encoder adopted by the host driver,
is deliberately after all of the above: it changes host emission, which is
the linear-target milestone's territory until it merges.

## Acceptance (milestone = stages 3a and 3b)

1. **Default bytes unchanged.** With neither flag set, every program in
   `corpus/scalar/` and `corpus/eval/*/` compiles to bytes identical to the
   baseline commit's; reuse `checks/gc-byte-identity.sh` from the
   linear-target PR once it merges, or an equivalent row until then.
2. **3a oracle green** over the fitting programs, with the skip list in the
   check's output.
3. **3b oracle green** over `corpus/control`, `corpus/closure`,
   `corpus/seqs`, `corpus/edn` through the compiled path.
4. **Size and time, dated**: the module with `LW_RUNTIME_COMPILE=1` versus
   without (raw, opt, brotli), and the time to compile and instantiate a
   20-line fn in node and in Chromium.
5. Rows `P9.0` onward in `checks/items.tsv`, STATUS.md updated, a
   DECISIONS.md entry per stage, a README paragraph, and
   `rt/wasm/README.md`'s load-order table updated.
6. Gates 1 and 7 green with `LW_ATTEST=0`.

## Work proposal

- **Who and when.** One agent, starting with stage 3a now: it is additive
  and needs no `src/` edits, so it runs beside the linear-target milestone 1
  without conflicts. Stage 3b's two flag points in `src/` wait for that PR
  to merge or for explicit agreement with its author. This machine is
  shared and each compile costs about a minute of CPU; two agents compiling
  is the limit.
- **Effort, as a guess to be replaced by the first measured stage.** 3a two
  to three days of agent time; 3b and 4 three to four days together, the
  encoder and the import plumbing being most of it; 5 one to two days. The
  census is the reason these numbers are not larger: the front end exists.
- **Risks, named.** Iso-recursive typing makes "same type across modules"
  fragile: if the rec group constant and the host's group ever differ by a
  byte, every cast fails at link time, loudly, which is the right failure.
  The boxed-only baseline will be slower than host-compiled code by a
  large factor on arithmetic; stage 5 measures it and fixnum fast paths are
  the first thing to add after. Redefinition visibility is explicitly out
  of scope (decision 6).
- **What this is not.** Not a replacement for the host compiler, not a
  path to the optimizing passes in the module, and not the let-go-written
  core question, which is a separate upstream conversation.

## Rules for whoever builds this

- Branch and pull request; CI publish check must stay green; never push to
  `main`; never rewrite history.
- Native lg is the oracle; `eval` is the second leg; a disagreement between
  compiled and `eval` is a bug in one of them, found by asking native.
- Named limits, not silent fallbacks: a form the baseline cannot compile
  raises a named error the caller can catch, and the REPL falls back to
  `eval` only when the user asked for compilation explicitly.
- Dates on every number. Decisions in DECISIONS.md with the next number.
