# wasm.str (P2.6 runtime half, 2026-10-01)

Strings, chars, keywords, symbols and floats as values, `str`/`pr-str`/
`print-str`, float formatting and the string natives, in the runtime dialect
(`str.lg`, ns `wasm.str`). Checked against native lg by
`corpus/intrinsics/str_test.lg` via `checks/run-intrinsics-native.sh`. Ground
truth: let-go 4e769212 built with go1.27.1. Paths are under
`~/projects-new/3p/let-go/pkg/` unless they start with `go:` (Go's
`internal/strconv`).

## Representation (D38)

| box | fields | notes |
|---|---|---|
| `Str` | bytes (`wasm/Bytes`, UTF-8), `[:mut :i64]` cached hash, -1 = not yet | hash is FNV-1a over the bytes, cached on first `hash` |
| `Char` | `:i32` rune | any 0..0x10FFFF, surrogates included (`rt/lang.go:6665`) |
| `Kw` | ns bytes or null, name bytes, hash | built from the full `ns/name` text, split at the first `/` unless the text is `/` (`vm/symbol.go:79`); hash = `hashUnencodedChars(text) + 0x9e3779b9`; interned |
| `Sym` | same layout, symbol hash | interned in the same table, distinct from a keyword of the same text |
| `Float` | `:f64` | |

`vkind` extends `sq/kind`: 17 Str (replacing raw Bytes, which is no longer a
value and traps), 19 Char, 20 Kw, 21 Sym, 22 Float. One runtime global
(`globals`, D39): the intern table (open addressing over `pv/Node`, load at
most 1/2), its count, and the print hook for foreign values.

## Index semantics (measured, lg 4e769212)

A let-go `String` is a Go string, so UTF-8 bytes, and its `RawCount()` is the
**byte** length (`vm/string.go:46`). The natives disagree on which unit they
use, and the port follows each one:

| op | unit | source |
|---|---|---|
| `count` | runes | `CoreCount` special-cases String: `len([]rune(s))` (`rt/lang.go:6105`) |
| `seq`/`first`/`rest`/`next` | runes | `String.Seq()` builds a `List` of `Char`s (`vm/string.go:259`) |
| `subs` | runes, mapped to byte offsets by walking | `rt/lang.go:3165` |
| `index-of`/`last-index-of` | runes | `[]rune` + `runeIndex` (`rt/lang.go:4103`, `:4707`) |
| `nth` | **bound by bytes, found by runes** | `Nth` takes the `vm.Indexed` path (`rt/native_prims.go:155`) and checks `i >= RawCount()`; `ValueAtOr` walks runes and returns `NIL` past the last rune (`vm/string.go:276`) |
| `compare`, `=`, hash | bytes | `string(a) < string(b)` (`vm/compare.go:69`) |

So `(nth "héllo" 5)` and `(nth "héllo" 5 :nf)` are both `nil` (5 is inside
the 6 bytes but past the 5 runes), while index 6 throws / returns `:nf`.
Reproduced on purpose, in D19's spirit. `compare` is byte order:
`(compare "￿" "𝄞")` is -1 where UTF-16 order would give 1. Invalid
UTF-8 decodes as U+FFFD of width 1, as `utf8.DecodeRune` (strings built by
this runtime are always valid; the decoder is exact anyway).

## Printing

`str` is `strValue` at the top level (`rt/lang.go:5006`): nil is `""`,
strings and chars raw, `##Inf`/`##-Inf` as `Infinity`/`-Infinity`, everything
else `Value.String()`. Nested values always print readably (`(str [\a "b"])`
is `[\a "b"]`, `(str [##Inf])` is `[+Inf]`). `pr-str` is readable at every
depth; `print-str` is raw at every depth (`print_method.go:30`, measured:
`(print-str ["a" \b])` is `[a b]`). Multiple args: `str` concatenates,
`pr-str`/`print-str` separate with one space. Seq kinds print `( … )`, a
pvec `[ … ]`; maps and sets go through the print hook (`set-print-hook!`,
owned by phm/phs).

String escapes (`String.String()`, `vm/string.go:309`), per rune:

| rune | written |
|---|---|
| `"` `\` | `\"` `\\` |
| TAB CR LF BS FF | `\t` `\r` `\n` `\b` `\f` |
| other < 0x20, and 0x7F | `\uXXXX`, uppercase hex |
| invalid byte | U+FFFD (`WriteRune(RuneError)`) |
| everything else (0x80+, U+2028, …) | raw UTF-8 |

Chars: `\space` `\newline` `\tab` `\return`, else `\` + the rune's UTF-8
(`vm/char.go:50`); a surrogate char encodes as U+FFFD, as Go's
`string(rune)`. The test checks every code point below 0x80 alone and inside a
string, plus non-ASCII samples.

## Floats (plan open question 7: decided)

`Float.String()` (`vm/float.go:60`): integral finite values print as
`FormatFloat(f, 'f', 1, 64)` (exact integer digits, then `.0`; `1e300` prints
all 301 digits), everything else as `FormatFloat(f, 'g', -1, 64)`: shortest
round-trip digits, `%e` when the decimal exponent is < -4 or >= 6 (`1e-07`,
`1.0000005e+06`), `NaN`, `+Inf`, `-Inf`.

Algorithm, all in i64 with no tables: `float-bits` recovers the IEEE bits
from the f64 (below), then a literal port of Go's multiprecision `decimal`
(`go:decimal.go`: Assign, Shift, Round, RoundUp/Down; 800 digits) produces
the exact decimal of `mant * 2^(exp-52)`, and `roundShortest` (Go 1.26
`go:ftoa.go:262`, the `bigFtoa` shortest path that Go 1.27's faster
`shortFloat` replaced; both yield the unique shortest-then-closest string)
cuts it. The integral path skips `roundShortest`. Changes from Go that do not
change digits: shifts go 59 bits at a time instead of 60 so `10 * 2^k` fits a
signed i64, and `leftShift` writes right to left into scratch instead of
using the `leftcheats` table.

`float-bits` is a stand-in for the `f64-bits` intrinsic D28 gives P2.2: it
scales `|x|` by exact powers of two into `[2^52, 2^53)`, reads the mantissa
with `f64-to-i64`, and rebuilds the exponent field (subnormals included). The
one thing float arithmetic cannot see is the sign of zero, so `float-bits`
uses one division, `(/ 1.0 x)`: the only non-dialect reference in `str.lg`,
whitelisted by name in the dialect test. NaN maps to Go's `math.NaN()` bit
pattern `0x7FF8000000000001` (`(hash ##NaN)` agrees).

Proven coverage:
- `corpus/floats/pr-str.expected` (281 lines from `gen.lg`: the plan's list,
  200 LCG values in [-1e6, 1e6], 1e-10..1e22, and 31 edge cases: subnormals,
  2^53 neighbours, the %e/%f switches, MaxFloat): **281/281 byte-exact**, and
  each line is re-derived live from native lg (stale snapshot fails).
  `(str x)` and `(hash x)` also match native for every corpus value; the hash
  match checks `float-bits` on all 281.
- A random sweep (scratch, not shipped, 2026-10-01): 10,000 doubles
  (4,000 17-digit mantissas over decimal exponents -330..306, 3,000 short
  decimals, 3,000 values below 1e5 with up to 8 fractional digits),
  **0 mismatches** against native `pr-str`; 200 s under the reference
  intrinsics, so not in the 30 s test.
- `roundShortest`'s `inclusive` flag (boundary included when the mantissa is
  even) cannot change a `Float.String()` result: a non-integral double's
  rounding boundary has at least 18 significant digits, more than the 17 a
  shortest result can have, and integral values take the `'f'` path. A mutant
  with `inclusive` forced false passes the corpus, as this predicts; a mutant
  that rounds down instead of to nearest fails 48 lines.

## Natives

Scalar: `str` `pr-str` `print-str` (arities 0-3 and `-seq` forms taking the
argument list, until the backend's variadic convention), `float->str`,
`name` `namespace` `keyword` (1, 2) `symbol` (1, 2) `char` `int` `compare`
`equals`/`equiv?` `hash`. String: `subs` (2, 3) `split` (core/split =
`strings.SplitN`, returns a List; clojure.string/split is lg code over it)
`includes?` (= string/includes?) `starts-with?` `ends-with?` `index-of`
`last-index-of` `trim` (`strings.TrimSpace`, Unicode spaces) `triml`
`trimr` (cutset ` \t\n\r`) `upper-case` `lower-case` `string-upper-case`
(clojure.string/upper-case: coerces with `str`) `str-replace` (literal
match, string or fn replacement; `""` matches before each rune and at the end)
`parse-long`. Collection views of strings: `count` `nth` `seq` `first`
`rest` `next`, which delegate every other kind to wasm.seq.

lg-defined fns that reach these through the backend for free:
`clojure.string/join`, `split`, `split-lines`, `blank?`, `capitalize`,
`replace`, `reverse`, `escape`, `starts-with?`/`ends-with?` wrappers.

## Gaps (named, not silent)

- Case mapping of non-ASCII text traps (`strings.ToUpper/ToLower` are
  Unicode). Regex separators/patterns are not in the value model.
- Errors whose let-go message embeds a value or a type name
  (`"3000000000 can't be coerced to int"`, `"value out of range for char: -1"`,
  `"cannot compare let-go.lang.String and …"`, `"keyword name must be a string,
  got …"`) trap with the static part until ex-info exists (P2.7); the test
  checks these with `same-err` (both throw). Static messages are compared
  exactly.
- `(int ##NaN)` traps: Go's `int(math.Trunc(NaN))` is platform-defined.
  `(last-index-of s x -5)` traps where native lg panics.
- `str-replace-first`, `format`, `println`/`pr` output, `re-*` not done.
- Strings inside wasm.seq collections reach seq.lg's single foreign hook slot
  (kind 18), which phs owns; `nested-through-seq-hooks` installs a test hook.
  Fixed by the seq.lg patch below.

## seq.lg patch (proposed, not applied)

1. Move the `Str Char Kw Sym Float` defstructs from `str.lg` into seq.lg's
   value-model block next to `Int`/`Bool`.
2. In `kind`, replace `(wasm/is? wasm/Bytes x) 17` with `(wasm/is? Str x) 17`
   and add `Char` 19, `Kw` 20, `Sym` 21, `Float` 22 before `:else 18`;
   `str.lg`'s `vkind` then becomes `sq/kind`.
3. Move `decode-at`, `rune-count*`, `string-seq`, `string-nth` (≈45 lines,
   intrinsics + `List` only) into seq.lg and call them where seq.lg now calls
   `string-seq-gap`: `seq-view` (k 17 → `string-seq`), `count*` (rune count),
   `nth*` (k 17 → `string-nth`, before the Indexed branch).
4. In `equiv?`, before the type-group test: Str by bytes, Char by rune, Float
   by `==`, Kw/Sym by text; in `hash*`: Str FNV (seq.lg's `fnv-bytes`), Char
   `hash-u64`, Kw/Sym their stored hash, Float `hash-u64` of `f64-bits` (needs
   the P2.2 intrinsic or `float-bits` moved too).
5. `fnv-elem` (hash of Range/Repeat/PVecSeq over non-int elements) still
   needs printing; leave the trap or give seq.lg a print hook.
