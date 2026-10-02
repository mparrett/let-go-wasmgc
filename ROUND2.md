# Round 2 plan (drafted 2026-10-01 evening; starts when Matt says go)

Scope agreed with Matt 2026-10-01: bugs first, then legmacs with the
interpreter deferred to a follow-up phase, quality tools run for data only,
skunkworks rules unchanged (nothing pushed, no PR, no issue; upstream held
until this round closes). Same machinery as round 1: every item is a row in
`checks/items.tsv`, done means its check exits 0, the runner verifies each
report by rerunning the row before committing, decisions go in
`DECISIONS.md` from D128.

## Finish line

`checks/gate.sh 6` green plus gates 1–4 still green on the same tree.
One named limit is allowed per phase and must be written in the gate
decision, as D127 did.

## Phase 5: pay the round-1 debt

| row | what | check |
|---|---|---|
| P5.0 | quality baseline captured for data only (let-go comment linter, aislop) | files under `corpus/quality/<date>/`; DONE 2026-10-01 |
| P5.1 | core tests 273/273 or each remaining failure named in a SKIP with a reason | `run-tests.sh --corpus` at bar 273 |
| P5.2 | the `to-array` row (P2.3) green | `checks/run.sh P2.3` |
| P5.3 | the INVENTORY gaps: `with-meta` on a variadic fn, identity hash of atoms/fns, `sort` incomparable-pair message, printing a fn | new oracle programs in `corpus/wasm/gaps/` |
| P5.4 | attestation reuse: a gate skips rows whose inputs (by `affected.sh` + content hash) are unchanged since their last green run | second `gate.sh 2` on an unchanged tree finishes in under 60 s with the same result |
| P5.5 | regression rows wired: `affected.sh` maps every `src/` and `rt/` path to P3.2 and P4.2 so legmacs work cannot silently break xsofy | `affected.sh src/lower_wasm.lg` lists P3.2 and P4.2 |
| P5.R | adversarial review of the round-1 gaps list (read-only agent, own corpus) | `corpus/review3/README.md` + fix rows filed |
| P5.GATE | | `gate.sh 5 && gate.sh 1 && gate.sh 2 && gate.sh 3 && gate.sh 4` |

## Phase 6: legmacs (interpreter deferred)

Census at round-1 end: 811/816 legmacs units compile; five named blockers
(three `binding` of non-var-table dynamic vars, two closures of arity 5).
Native twins: 146 reached, 37 missing
(`corpus/quality/2026-10-01/legmacs-twins.txt`). Of the 37, three are
subsystems, not natives, and are OUT of this phase by decision:
in-process `eval` (needs a compiler or interpreter in the module),
`go` blocks (needs a scheduler on JSPI), regex beyond the RE2 subset.
They go in `corpus/natives/SKIP-legmacs` with reasons and become Phase 7.

| row | what | check |
|---|---|---|
| P6.0 | legmacs natives: the 34 ordinary missing twins | `native-twins.sh natives-legmacs.txt` MISSING 0 outside the SKIP list |
| P6.1 | backend blockers: `binding` of dynamic vars via the var table; closure arity > 4 | `census.sh legmacs` 816/816, 0 other |
| P6.2 | legmacs' own test suite under the backend (9 files in `~/projects-new/3p/legmacs/test`) | `run-tests.sh` over `corpus/legmacs-tests.txt` at a bar set by the first measured run, raised to all-pass minus named limits |
| P6.3 | legmacs headless oracle: scripted editing session, buffer dump byte-identical native vs emitted | `checks/legmacs-parity.sh N` |
| P6.4 | legmacs in the browser on the lower-wasm host (xterm, key input, resize) | `browser-boot.sh --legmacs` |
| P6.5 | size and boot table for the legmacs module beside xsofy's | `size-boot.sh --legmacs` |
| P6.R | adversarial review of the legmacs surface (read-only agent, own corpus) | `corpus/review4/README.md` + fix rows filed |
| P6.GATE | | `gate.sh 6` |

## Phase 7 (follow-up, not in this round, needs its own decision)

In-module `eval` for legmacs' REPL and eval-last-sexp. Two shapes to
decide between: an interpreter over the reader's data in the runtime
dialect (small, slow, no new backend work), or the IR pipeline compiled
through the backend so the module can lower and instantiate new wasm at
run time (large; needs `WebAssembly.instantiate` from inside the host ABI).
`go` blocks and full regex ride with whichever is chosen.

## Process (what round 1 did that we keep, plus the three additions)

- Rows before code: an item's check must exist and exit 2 before an agent
  is dispatched on it.
- At most three Opus subagents; `src/` items one at a time; Sonnet for
  mechanical corpora. Every agent reads `AGENTS.md`.
- Reviewer slot per phase: a conversational Opus dispatch with a read-only
  brief and its own corpus directory, as `corpus/review` and
  `corpus/review2` were. Not `/code-review`.
- New: quality tools rerun at each gate into `corpus/quality/<date>/`, data
  only, no row gates on them this round.
- New: `TOUR.html` and the preview pages regenerated at the final gate by
  the runner, not afterwards.
- New: a cost line per gate in STATUS.md from the session transcript
  tally. Round-1 baseline (summary doc, "Cost of the campaign"): ≈2.0 B
  cache-read tokens, ≈$4.3k–5k at assumed list prices, 85% of it the Opus
  subagents, for 22 h and 53 commits.
- Nits found while playing 2026-10-01 night: `build-info.json` 404 from the
  shell (serve script should write one); `os/getenv` is nil in the module
  (runtime does not import env.getenv yet; node host's `--url` is the
  workaround for seeding); `lw run` / `lw build` one-command wrappers for
  node and wasmtime (P6 candidate).
