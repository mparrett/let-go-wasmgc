# tools/ — the native-twin instrument (P2.8)

The question these answer: which Go natives does a program reach that the
wasm runtime does not provide yet? Four pieces, run from `dev/lower-wasm/`
with the pinned lg (`$LG`, resolved by `checks/env.sh`):

| Tool | Output |
|---|---|
| `lg tools/native-inventory.lg` | `corpus/natives/inventory.tsv`: every native var in a stock lg |
| `lg tools/twin-manifest.lg` | the natives the runtime claims (`:twin` markers) |
| `lg tools/twin-manifest.lg --propose` | `corpus/natives/manifest-proposed.tsv`: the markers to apply |
| `tools/reach.sh <root> <prefix> [ns…]` | a reach list (`corpus/natives/natives-*.txt`) |
| `checks/native-twins.sh <reach-list>` | what is missing; exit 0 iff nothing |

## Inventory

The var list is runtime truth: every public var, in every ns a stock lg
loads, whose value is a `NativeFn`. The Go sources supply only `file:line`,
arity and registration style, and are read with `git show` at the SHA the
binary reports in `lg -version`, so a let-go checkout that has moved on does
not skew them. Columns:

- `arities`: `2,3` for fixed arities, `>=N` for a variadic Go signature, `?`
  when the Go side checks arity at run time (the `func(vs []vm.Value)`
  proxies). Most `//lg:native` prims are declared `vs ...vm.Value`, so `>=0`
  means "checked inside", not "takes anything".
- `registered-via`: `lg:native` (the directive `cmd/lgprimgen` consumes),
  `ns.Def`, or `other` (`LookupOrAdd(vm.Symbol(…))` in `compiler/eval.go`,
  or an lg-level `(def ref atom)` alias in `pkg/rt/core/*.lg`).
- `match`: `exact` when the site's ns and name both agree; `name` when the
  Def's ns is computed (`installMathInto(nsName)`, `defStaticNS(nm)`) and
  only the name matched; `computed` for the exception-constructor spellings
  built by string concatenation. A `name` row can point at the wrong one of
  two same-named Defs; the source is then a hint, not proof.
- `same-fn-as`: the canonical member when several vars hold the very same
  NativeFn (`string/trim` is `core/trim`, `hash/xxh3-64` is `xxh3/Hash`). A
  twin for one member covers them all.

`corefns/` directives are ranked last: there the generated registrar only
records a direct-call descriptor, and the var itself is Def'd in `lang.go`.

## Marker convention (proposed decision)

A runtime defn that implements a native says so with `:twin` metadata on its
name, beside D24's `:intrinsic`/`:wasm`:

```clojure
(defn ^{:twin "core/first"} first [x] …)
(defn ^{:twin ["core/count" "core/hash"]} f [x] …)   ; one defn, several natives
```

The value is the native's `ns/name` spelled with runtime ns names (`core`,
`string`, `os`), as in the inventory and the reach lists. The lg reader turns
`^{…} name` into `(with-meta name {…})`, which `twin-manifest.lg` reads from
source without loading the runtime. The form passes every dialect test
unchanged: markers on six defns across pvec/phm/phs/seq/str, including a
multi-arity defn and a vector value, gave `checks/run-intrinsics-native.sh`
66/66 tests, 0 failures (scratch copy, 2026-10-01). A claim of a name that is
not a native in the inventory prints a `WARN` in the twin report.

Why metadata rather than a per-file `twins` table: the claim sits on the
defn it describes, so renaming or deleting the defn takes the claim with it.

## Applying the proposal (P2.9)

`manifest-proposed.tsv` name-matches today's public runtime defns to the
inventory, with a confidence column:

- `high`: same name, one defining file.
- `medium`: same name, but the string-kind copy still lives in `str.lg` until
  D48 folds it into `seq.lg`; or a renamed entry with the same semantics
  (`equals` → `core/=`, which is binary where `=` is variadic).
- `low`: a one-kind entry point (`massoc`, `vnth`, `sconj`, …). Mark the
  dispatching entry P2.9 builds, not these.

Until any marker exists, `checks/native-twins.sh` counts every proposed row,
`low` included, under a `PROPOSED MANIFEST` banner; once one marker lands it
reads only the markers.

## Reach lists

`tools/reach.sh` calls `../emit-wasm-probe/reach.lg` in place from a scratch
dir of symlinks (reach.lg writes to its cwd and slurps fixtures relative to
it). The header gives the invocations that reproduce the probe's xsofy and
legmacs lists, and `natives-shared.txt` is their `comm -12`.
