# How work moves through this repository

One page for the conventions the two of us settled on the issue board, with
a pointer to where each is enforced. The rules themselves live in
`checks/state-template/00_governance.md`; this page is the map.

## Issues

Issues are git-issue notes in this repository (`git issue list`, `git issue
show <id>`; the tool is
[git-issue-tracker](https://github.com/mparrett/git-issue-tracker)). An issue
is written so that closing it is mechanical:

    <title: the post-state, as a commit subject would say it>

    <one paragraph: what is wrong or missing, and why it matters now>

    Facts that close it (status, then the witness each needs):

    - F1 <claim>: <witness: a command and its exit, or a file:line>
    - F2 ...

    Measurements that close it, each with its conditions (revision, load
    average, run count, through checks/quiet.sh):

    - M1 ...

A fact is a claim about the tree; a measurement is a number with its
conditions. An issue with neither is a note, not an issue. Dependencies go
through `git issue dep add <a> blocks <b>`, so `git issue ready` lists what
can start.

## Workflow state

`checks/state.sh` keeps an issue's working state as entries led by
`State: NN_name` in a local journal, the authority; with `LW_STATE_POST=1` an
entry is also posted as a comment on the issue, for others to see (where the
shared copy lives is 562dff4). `checks/workflow.sh` and `checks/workflow.mk`
wrap the steps a script can decide:

    make -f checks/workflow.mk start      # in-flight list -> 05_inflight
    make -f checks/workflow.mk baseline   # the rows that fail on the base
    make -f checks/workflow.mk rows       # red on the base, green on the change
    make -f checks/workflow.mk gate PHASE=<n>
    make -f checks/workflow.mk pr-ready TITLE=... BODY=file   # title and body lint
    make -f checks/workflow.mk pushed ci

`checks/state.sh inflight` lists every in-flight item: issues in progress or
review, worktrees with commits not on the base, open PRs. A new issue is not
taken while an in-flight item of the caller's can move.

## Commits

Commit subjects are Conventional Commits 1.0.0: `type(scope): description`,
where the scope is the area the old prefixes named (`host`, `rt`, `checks`,
`corpus`, `docs`). `checks/subject-lint.py` enforces it through the commit-msg
hook that #68 adds to `.pre-commit-config.yaml` (`make -f
checks/workflow.mk hooks` installs the hooks). Every commit, including those on a
branch, since a squash merge keeps whichever subject the PR carries. A body
says why; a trailer `Issue: #<id>`, `Fixes: #<id>` or `Closes: #<id>` names the
board item.

## Reviews and merges

A PR is reviewed at its head commit, in a worktree detached at that commit,
and the review names the commands it ran and their exits. A PR merges when
CI is green, it has a review, every concern in the review is answered, and
each fix was verified at the head being merged. A change proves itself
with gate 2 and the oracle rows of the programs it touches; the GC byte
guard (P8.0) is advisory and decides nothing (D228).

## Gates

`checks/gate.sh <n>` runs phase n's rows and prints TAP 13: the version
line, the plan `1..N`, `ok`/`not ok n - <id>` per row with `# SKIP <reason>`
and `# TODO git-issue:<id>` directives, and under each row a YAML block with
`duration_ms` (the row's work) and `wait_ms` (time blocked on the slot pool).
Each row also appends one line to the per-machine timings ledger
`$LW_STATE/gate-times.tsv` (or `$LW_GATE_TIMES`), untracked. The row exit
codes, the directives and the owning-issue column are D228 (#69); the
version line, the duration blocks and the ledger are D229 (#71); P0.7
checks both. The GC byte guard (P8.0) is advisory. A general
`LW_REQUIRE_<runtime>` opt-in is f1a846c's proposal; only
`LW_REQUIRE_BROWSER` exists.

## Records

- `DECISIONS.md`: numbered design decisions; a new one takes the next number
  (whether it starts as a board issue is 2a446d9).
- `STATUS.md`: the dated row table of work items.
- `FINDINGS.md`: things learned that are not decisions.
- The issue board: anything in flight, and every rule before it is settled.
