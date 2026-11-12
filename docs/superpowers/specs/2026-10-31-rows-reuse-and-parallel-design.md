# Rows that reuse attested results and run in parallel

Written 2026-10-31. It applies to `checks/workflow.mk`'s `rows` and
`baseline` targets and to `checks/gate.sh`, on every lane. It builds on P5.4
(attestation, `checks/attest.sh`) and on the per-backend evidence design
(git-issue:bc33496).

## Why

The full row set on the llvm-parity branch, 119 to 134 rows, took 3.9 to
4.2 hours in its last runs, and a pin move makes the last full run worthless. Most
of that time reruns rows whose inputs have not changed since they last
passed, one row at a time:
- `workflow.sh rows` runs each row through `run.sh` with `LW_ATTEST=0`, one
  after another, so the dev loop never reuses a result and never overlaps
  two rows.
- `gate.sh` already has both: rows run `LW_GATE_J` at a time (default 2),
  and a row whose input key (`attest.sh key`) matches its last green run is
  reported `ok … (attested)` without running. It also keeps per-row timings
  in `gate-times.tsv`.
- But a phase-gate decision is taken with `LW_ATTEST=0`, because the key
  sees only what `affected.sh`'s table names for a row: "the gate is only as
  honest as that table". Nothing checks the table.
- `rows` with no list reads `git diff HEAD`, so after a commit it finds
  almost nothing, and a full run is a hand-made list.

## Goals, non-goals, anti-goals

Goals:
- A row that passed with the same inputs on this machine is not run again,
  in the dev loop or a gate decision.
- Rows that can share the machine run at once; the ones that cannot run
  alone.
- After a pin move, the rows that depend on lg run once, and nothing else.

Non-goals:
- Sharing results between machines (the ledger stays per machine, as agreed
  on git-issue:bc33496).
- Making any row faster on its own (git-issue:d2b7f41 is that work).

Anti-goals:
- A row reported green whose real inputs changed.
- A timing row (P12.37's warm bound, the benchmarks rows) measured while
  other rows load the machine.

## Part 1: reuse, made trustworthy

The mechanism exists (`attest.sh key`, `record`, `fresh`). What it needs is
a key that sees everything a row reads.

- **The key covers the toolchain.** Today it hashes the declared files, the
  external corpora, the row's `items.tsv` line, the lg binary and node's
  version. Add the versions of clang and lld, Go, and the wazero runner's
  build, for the rows that use them (declared in the table as `tool:clang`
  and so on), and the `LW_*` variables a row reads.
- **The table is audited.** An audit row runs a row in a worktree that holds
  only the row's declared inputs (a sparse checkout of the table's paths)
  and requires the same verdict as in the full tree. A row whose verdict
  differs reads something the table does not name, and the audit names it.
  The audit runs on every row whose table line changed, and on the full set
  when the pin moves.
- **Decisions may use reuse once a row is audited.** The audit's verdict is
  recorded in the per-machine ledger beside the row's key and table line,
  and `gate.sh <n>` reuses a row only when the ledger shows the audit at the
  current table line; an unaudited row runs. The audit runs locally only: CI
  has no ledger, so CI keeps running every row fresh.
- **A reused row says so where the decision is read.** Reuse changes what a
  green decision means: verified at a tree with the same declared inputs,
  not at this head. So the row's TAP line carries the attestation key's
  short form and the date of the audit that licensed the reuse, and the
  evidence note a PR carries holds the same two fields for each reused row,
  so a reader can tell a run from a reuse without the ledger.
- **Per-backend cells use the same key.** git-issue:bc33496's cells are
  recorded against the row's key, so a reused row reports the cells it
  recorded.

## Part 2: rows run through the gate's scheduler

- **`rows` and `baseline` become `gate.sh` over a row list,** with
  attestation on, instead of a separate serial loop. The output stays
  `<row> <exit> <seconds>s`, now from the gate's timings, and each row keeps
  its log (#83).
- **Rows that must run alone say so.** An `items.tsv` column `run` takes
  `shared` or `alone`, so a third mode has somewhere to go. P12.37, the
  benchmarks rows and any row that runs `quiet.sh` are `alone`. An alone
  row's bound is measured on an emptied machine, so the scheduler waits for
  the slot pool to drain, not only for the rows before it in the list,
  before an alone row starts, and starts nothing else until it ends.
- **`rows` with no list is the rows whose key moved,** not `git diff HEAD`,
  so a commit does not hide its rows.
- **Concurrency defaults to the slot pool's size** (`LW_SLOTS`), since each
  row's programs already queue for slots.

## Acceptance

- On an unchanged tree, the full set reports every audited row attested and
  exits in under a minute.
- A planted undeclared input (a row reading a file its table line omits) is
  reported by the audit, and the row is not reused.
- After an edit to one runtime file, `rows` runs exactly the rows whose
  table names `rt/`, and the 134-row set's wall time on a quiet machine is
  recorded before and after part 2.
- P12.37 meets its bound run by the scheduler and run alone, both measured
  in one session, so the comparison is on the same machine state.

## Decided

- Reuse is per machine (git-issue:bc33496's answer); a fresh clone runs
  everything once.
- `rows` becomes the gate's scheduler rather than a second loop.
- A reused row reports its key's short form and its audit's date, in its
  TAP line and in the PR's evidence note.
- The column is `run`, with `shared` and `alone`; an alone row waits for
  the slot pool to drain.
- The audit runs locally only, and its verdict lives in the ledger beside
  the key and the table line.

These were agreed on git-issue:50d286e (2026-11-01).

## Risks

- **The audit's worktree differs from the full tree in ways that matter**
  (an ignored cache such as `src/.rtlib`): the audit seeds the same ignored
  caches the row's declared inputs build, or it reports a false gap.
- **The audit tests verdicts, not reads.** A row that reads an undeclared
  input and still returns the same verdict passes the audit, and its key
  stays incomplete until that input changes the verdict. A read trace under
  the audit (the files the row's processes open, diffed against its table
  line) closes the gap; it becomes a follow-up row if a planted silent read
  gets past the verdict audit.
- **Two rows that write the same cache** (the runtime snapshot, the
  wazero runner) race; the caches already write to a temporary name and move, and
  the scheduler serializes rows the table marks as writing one.
