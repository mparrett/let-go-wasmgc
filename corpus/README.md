# corpus

Inputs and expected outputs for the checks in `checks/items.tsv`. A program
here proves one behavior: compiled through the backend, it does what native lg
does (`checks/oracle.sh`; see "Checks" in the top-level README). Expected output
is native output, never the backend's WAT or bytes.

## Rules

1. **One file per behavior, dense.** A file walks a behavior through its
   cases (the edges, each value kind it accepts, the error path), printing one
   line per case. Fifty one-expression files for the same behavior are one file.
2. **A bug fix adds a case to the file that owns the behavior**, with a comment
   naming the issue. No file per bug or per probe: `checks/corpus-lint.sh`
   refuses names like `bug-*`, `probe-*` and `pNN-*`.
3. **Look before adding.** Grep the corpus for the forms first and extend the
   file that owns them. A new file needs a behavior no file owns; a new
   directory needs a topic (below) and a `README.md` that says what the topic
   covers and which check runs it.
4. **Don't repeat another layer** (next section). A behavior that a suite or the
   runtime's native tests already pin needs a corpus case only when it fails
   compiled and the suite can't isolate it.
5. **Generated sets are regenerated, not edited:** `opmatrix/`, `maporder/`,
   `floats/`, `edn/`, `typed/` keep their generator beside the output.
6. **Results are records, not tests.** Gate logs, census tables, result TSVs
   and reports don't grow the test set; prefer out-of-tree logs to new records.
7. **Growth comes from issues.** `checks/corpus-budget.tsv` gives each
   top-level directory a base (files, KB, the date it was set) and the topics it
   serves. Its ceiling is the base plus 2 files and 16 KB for each issue
   given the label `corpus:<topic>` (one of its topics, or a topic below one)
   since that date, a new issue or an existing one, so tagging the issue a test
   answers is what makes room for the test. A label may go below a topic when
   that is clearer (`corpus:lang/types/protocols` counts for `lang/types`), and
   issues may nest with git-issue's `parent_of`. An untagged child takes its
   nearest tagged ancestor's topics, counted from the later of that label's
   date and its own creation. `checks/corpus-lint.sh` (row P0.2, a pre-commit hook) enforces it.
   Raising a base, adding a row or changing topics cites an issue in the commit
   (`Issue: #<id>`; a commit-msg hook checks). After deleting,
   `checks/corpus-lint.sh --lower` brings the bases down. The `review*/` rows
   have no topics: closed, they only shrink. Without the issue notes fetched
   the lint sees the bases alone, which is stricter, never looser.

## Who tests what

| layer | proves | where |
|---|---|---|
| runtime, natively | `rt/wasm` semantics under native lg, before compiling | `intrinsics/*_test.lg`, `checks/run-intrinsics-native.sh` |
| topic programs | compiled == native, one behavior per file | the topics below, `checks/run-corpus.sh` |
| refusals | an unsupported form is a named compile error | `refused/`, `checks/refuse.sh` |
| suites | breadth on deftests written by others | `core-tests.txt`, `legmacs-tests.txt`, `jank/`, `checks/run-tests.sh`, `checks/jank-suite.sh` |
| apps | whole programs: boot, world and screen parity | `xsofy/`, `legmacs/`, `checks/world-parity.sh`, `checks/browser-boot.sh` |
| coverage | every unit of the app code compiles | `census/`, `checks/census.sh` |

## Proposed layout

Today's directories follow the work's history (phase rows, review rounds); the
proposal sorts by topic so that "who owns this behavior" has one answer. The
topics are the `corpus:` label vocabulary (the `# topics:` line of the budget),
and each of today's directories lists the topics it serves, so labels work
before anything moves. It is
a proposal: a directory moves in its own commit, with its `items.tsv` and
`checks/affected.sh` paths, and nothing moves until it is agreed.

| topic | holds | from today's |
|---|---|---|
| `lang/numbers/` | arithmetic, overflow, comparison, float printing | `scalar/`, `opmatrix/`, `typed/`, `floats/`, `wasm/floats.lg` |
| `lang/control/` | try, throw, finally, loop, recur, error values and text | `control/`, `wasm/control-rt.lg`, `wasm/errors.lg` |
| `lang/fns/` | closures, arities, variadics, apply | `closure/`, `wasm/arity/`, `emit/arity-*` |
| `lang/vars/` | def, binding, set!, namespace init, constants | `consts/`, `wasm/dynvars/`, `wasm/nsinit/` |
| `lang/colls/` | seqs, maps, sets, vectors, ordering, hashing | `seqs/`, `maporder/`, `hash/`, `wasm/{maps,sets,vectors,seqs,hashing}.lg` |
| `lang/strings/` | strings, regex, printing | `wasm/strings.lg` |
| `lang/reader/` | reading data and code | `edn/`, `wasm/reader.lg`, `eval/reader/` |
| `lang/types/` | deftype, defrecord, protocols, multimethods | (new; `wasm/` meanwhile) |
| `runtime/` | twins and the runtime's native tests | `natives/`, `intrinsics/` |
| `eval/` | the in-module evaluator | `eval/`, `eval-buffer/` |
| `host/` | the host ABI: output, keys, env, stack depth | `host/`, `emit/host/`, `wasm/getenv/`, `depth/` |
| `refused/` | named compile errors | `refused/` |
| `targets/linear/` | the linear-memory target | `linear-gc/`, `linear-numeric/`, `refused/linear/` |
| `targets/llvm/` | the llvm target's own runtime and limits | (new) |
| `suites/` | others' test suites and their lists | `*-tests.txt`, `jank/`, `jank-harness/` |
| `apps/` | whole programs | `xsofy/`, `xsofy-console/`, `legmacs/`, `examples/` |
| `records/` | results, not tests | `gates/`, `quality/`, `census/` tables, `*-results.tsv`, `*-report.md` |

`wasm/pending/` and `wasm/gaps/` (programs that don't match yet) become cases
in their topic's file, each marked with the issue that tracks it. The `review*/`
directories (about 1,500 files) dissolve: a fixed bug becomes a case in its
topic's file, a probe that adds nothing a topic file doesn't already cover is
deleted, and a refusal goes to `refused/`.
