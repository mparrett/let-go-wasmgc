# corpus/depth — D89: does xsofy's stack fit under JSPI?

**Verdict: fits.** xsofy's deepest call stack, counted in lg fn frames, is
**20** (as of 2026-10-01, xsofy canonical checkout, lg 4e769212). The browser
budget D89 measured is about 5,000 frames of the smallest boxed shape
(Chromium 148: 5,000 pass, 7,000 fail; node 25 without flags the same, with
node-host's flags 1,000,000). The margin is two orders of magnitude even
after the allowances below.

## Method

`measure.lg` wraps core's `fn` macro (and labels `defn`/`defn-` bodies with
the var name) before xsofy loads, so every fn body xsofy compiles counts a
frame on entry and uncounts it in a `finally`. This includes anonymous
fns, named-fn self-recursion, letfn and `lazy-seq`/`for` thunks, which a
var proxy would miss. A fn-level `recur` stays a loop. The world must not
change: `measure.lg load corpus/dump-world.lg 1 200` and the plain
`dump-world.lg 1 200` print byte-identical dumps (20,831 bytes, checked with
`cmp`).

Run: `lg -source-paths ~/projects-new/3p/xsofy corpus/depth/measure.lg depth 20 200`
(about 12 min). Raw output: `results-2026-10-01.txt`. Coverage: 20 seeds × 200
turns × three fixtures (bench/native.lg's `:wait`, `:autoex`, `:descend`), each
starting with `make-world 79 30 seed` (so world generation is included). Every
turn also runs `render-full` and `render-dirty` on the new world, with
`term/size` pinned to 100×36 and output discarded, and 0 render errors.

## Results

| fixture | min / median / max deepest stack per seed |
|---|---|
| wait | 16 / 18 / 19 |
| autoex | 16 / 18 / 20 |
| descend | 16 / 18 / 19 |

The deepest chain (autoex, seed 16) is `update-world → autoexplore-step →
player-move → update-fov → compute-fov → cast-octant ×12 → blocked? →
transparent? → in-grid?`.

Top 10 fn bodies by the deepest stack position reached: `terrain/in-grid?` 20,
`terrain/tget` 20, `hash/valid-codepoint!` 19, `terrain/transparent?` 19,
`fov/blocked?` 18, `fov/cast-octant` 18, `hash/conj-codepoint->utf8` 18,
`hash/conj-utf8-char` 17, `hash/u64-shr` 17, `hash/conj-int->8-be` 16.
The render path never gets into the top 20.

**One non-tail recursion matters: `fov/cast-octant`** (recursive
shadowcasting), which reached 13 simultaneous frames. It is bounded by the FOV
radius, because each recursive call advances `row` and stops at
`row > radius` (fov.lg:23). The player's radius is `view-radius` 12
(world.lg:59), NPC perception defaults to 12 (percept.lg:35), and bestiary
light radii go up to 20. Everything else nests at most twice (`deep-merge`
over a nested map, `ai`, `damage-entity`, `encode-salt-into`).

**Lazy realisation chains:** none of any depth. `lazy-seq` thunks from xsofy
code are counted above. xsofy's own `lazy-seq` uses are in `check.lg` (the
property-test library, which is not on the game path), and every `concat` is
realised at once (`vec`, `set`, `distinct`). No `reduce concat`
accumulation exists.

## Not counted, and the allowance for it

- Frames inside let-go natives and pre-compiled core fns (`map`, `reduce`,
  `update`, `swap!`, `sort-by`, ...). In wasm these become runtime frames
  (`wasm.seq`/`wasm.core` helpers, `$rt_invoke*`) between user frames, a few
  per HOF callback.
- The game-loop shell above `update-world`: `-main → game-loop →
  play/run-play-loop → ui/run-loop → step`, about 10 frames.
- Frame size. xsofy fns have more locals than D89's `down`, so each V8 frame
  is larger.

A pessimistic allowance multiplies the 20 user frames by 5 for runtime
helpers, adds 10 × 5 for the shell, and assumes frames 10× the size of `down`.
That is 150 "big" frames against a budget of about 500 such frames. It still
fits, and the first thing that could break it would be a much larger FOV
radius, which grows linearly and visibly.

D89's fix-in-the-backend clause (loops or an explicit stack) is not needed for
P4.1.
