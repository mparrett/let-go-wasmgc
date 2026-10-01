# Brief for every agent on the lower-wasm campaign

Read in this order: this file, `README.md`, `checks/items.tsv`, your item's
row, then the plan (`../../docs/project_incoming/letgo-emit-wasm-plan-2026-09-30.md`,
sections 3 and 4) and `DECISIONS.md`. Then read the probe you are extending:
`../emit-wasm-probe/lower_wasm.lg` and `ext/README.md`.

Rules (not negotiable):
1. **Skunkworks.** Nothing leaves this machine: no `git push`, no `gh`, no
   issue, no PR, no comment anywhere. Do not commit; the orchestrator commits.
2. **Write only under `dev/lower-wasm/`** (and your scratch dir). The let-go
   checkout at `~/projects-new/3p/let-go` is read-only reference; the xsofy
   and legmacs checkouts too. Never modify them.
3. **Toolchain:** lg = `~/projects-new/3p/lg-bin/lg-4e76921230` (let-go main
   4e769212; older lgs lack the `ir.*` API). node 25, wasm-tools 1.256,
   wasmtime 47, `/opt/homebrew/opt/binaryen/bin/wasm-opt`. Install nothing.
4. **Done means `checks/run.sh <your-id>` exits 0.** If the check script in
   your row does not exist, writing it is part of your item. A check must be
   able to FAIL: before you finish, break the feature once and watch the check
   go red, then fix it (record this in your report).
5. **Match means `checks/oracle.sh`.** Never compare by eye.
6. Shell is zsh in interactive use but scripts are bash: no word-splitting
   of unquoted vars in zsh; `mv`/`cp` are `-i` aliased interactively, use
   `command mv`. Background nothing that outlives you.
7. **Report** = what you built (files), the check command and its output,
   the falsification step, anything you could not do, and any decision you
   had to make that is not in DECISIONS.md (propose it; do not edit that
   file). Keep it under a page. No subagents.
