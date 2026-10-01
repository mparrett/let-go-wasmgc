# corpus/xsofy — P3.2: xsofy's world through the backend

`checks/world-parity.sh [--keys wait|autoex|descend|deep|<str>] [N] [turns]`
compiles `corpus/dump-world.lg` once (xsofy on `-source-paths`, read from
`LG_ARGS` by `checks/wasm-run.sh`) and compares its dump with native lg per
seed through `checks/oracle.sh`. Results as of 2026-10-01 (lg 4e769212, xsofy
0c38395):

| run | result |
|---|---|
| 20 seeds × 60 turns, wait | 20/20 MATCH |
| 5 seeds × 200 turns, autoex (`x` then waits) | 5/5 MATCH |
| 5 seeds × 200 turns, descend (`>` then waits) | 5/5 MATCH |
| seeds 7, 9, 10 × 200 turns, deep (98 × `x`, then `>`) | 3/3 MATCH, all reach floor 2 |

measure.lg's autoex and descend fixtures never leave floor 1 (`>` only routes
to stairs already in `:memory`, and with waits after it nothing walks there),
so `deep` is the fixture that covers `change-floor` and a second floor.
Autoexplore kills the player on every seed 1–5 before turn 200, so death is
covered too.

## Root causes found (each has a repro here; native output in its header)

| repro | cause | fixed in |
|---|---|---|
| repro-01 | `term/size` is nil off a TTY natively; run.mjs said 80×24, so each descend drew the title card (ANSI) on stdout | run.mjs reports (-1,-1) = no terminal; `lw-ext/term-size-v` |
| repro-02 | a library def's Var is bound at compile time; lg's `vector?`/`string?` see through a Var, so the `:def` target looked like a vector literal | `typed-aux?`, `template?`, `string-const?`, `symbol-const?` exclude Vars |
| repro-02 | `^:private` reads as a `(with-meta name ..)` def name, which ir.build evaluates | driver drops the name's meta for library defs |
| repro-02 | `binding` of a program dynamic var (xsofy.opcontext/*op-context*) | saved/restored var-table global (`push-var!`/`pop-var!`) |
| repro-04 | typeinfer's self-call test matches by name: string/ends-with? → core/ends-with? was typed :int | `self-call?` false on a same-named foreign call (UPSTREAM) |
| repro-05 | unbound natives on the path: core/long, ints, re-find, string/join and ends-with? (string.lg is lg code), *assert*, *out*/*err*, push-binding!, let-go.core/now (trapped at ui load) | lw_ext fills, string.lg compiled like core.lg, var constants |
| repro-06 | os/args was nil, so the dump ignored its seed | `env.argc`/`env.arg` imports (proposed) |
| (census) | `validate after licm` on bfs-path (reached by descend) | rebuild without licm on that error (UPSTREAM) |
