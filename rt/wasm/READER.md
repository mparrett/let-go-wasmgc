# wasm.reader (P3.0, 2026-10-01)

`read-string` for data, in the runtime dialect (`reader.lg`, ns
`wasm.reader`, loaded after `core.lg`). D70: let-go's `edn.lg` wraps a Go
native, so there is no lg reader to compile; this is a port of the Go one.
Ground truth is let-go 4e769212 built with go1.27.1. Citations are
`~/projects-new/3p/let-go/pkg/compiler/reader.go` unless stated.

xsofy calls `core/read-string` (not `edn/read-string`) at `xsofy/seed.lg:27`
and `xsofy/console.lg:94`. That native is `newDataReaderWithResolvers` +
`ReadSkipNoValue` (`eval.go:241`): the first form, data semantics
(metadata attached, real sets, duplicate keys rejected, `#_` splices
nothing), leading comments and discards skipped, the rest of the input
ignored.

## API

| fn | args | result |
|---|---|---|
| `read-string` `^{:twin "core/read-string"}` | a Str | the first form; raises on error |
| `read-string*` | a Str, a boxed rune index | `[form end]`, end the rune index after what was consumed; positions in messages count from `start`, as reading `(subs s start)` would |

A non-string argument raises `read-string: expected String, got <%T>` with
Go's type name for the kinds the runtime has (`*vm.Nil`, `vm.Int`,
`vm.ArrayVector`, `*vm.List`, `*vm.PersistentMap`, …; `eval.go:247`).

## Shape

One reader state per call: `RS` (bytes, length, byte position, rune
position, line, column) and `Aux` (lastCol, lastRune, lastSize, the error
chain, the caused-by-EOF flag, a Void marker, the `:line`/`:column`
keywords). `new` takes at most 7 fields, hence two structs. No runtime
global. Read functions return a value, the Void marker (comment, discard),
or the state itself on failure, which mirrors Go's `(Value, error)` returns
without try/catch and lets `#_` swallow a non-EOF error as
`readFormComment` does (`:1962`). `next!`/`unread!` track line and column in
runes as `next`/`unread` do (`:151`, `:167`), so positions in messages match
without a rescan. Input is UTF-8 bytes decoded by `wasm.seq/decode-at`
(invalid bytes are U+FFFD of width 1, as `bufio.ReadRune`).

## Token table

First rune after whitespace (`unicode.IsSpace` or `,`), as `Read` (`:260`)
dispatches it:

| first rune | reads as | notes |
|---|---|---|
| a Unicode digit (Nd) | number token → the number cascade below | `٣` starts a number and is `invalid number: ٣` |
| `+` `-` then a digit | number | `+` or `-` at end of input is an EOF error, not a symbol |
| `(` | list, with position meta `{:line L :column C}` | `meta` reads FormSource (`lang.go:3456`) |
| `[` | vector (no meta) | |
| `{` | map: even count, no duplicate keys (`=`), built on a transient as `NewArrayMap` | order: array-map ≤ 8, HAMT past (D29) |
| `#{` | set, conj in order, duplicate element is an error | |
| `"` | string, escapes `\t \r \n \b \f \\ \" \uXXXX` (surrogate pairs combined) | |
| `\` | char: one rune, `space tab backspace newline formfeed return`, `uXXXX`, `oNNN` | `%x`/`%o` scan quirks below |
| `'` `@` `~` `~@` | `(quote x)` `(deref x)` `(unquote x)` `(unquote-splicing x)` | no meta |
| `#'` | `(var sym)`; any other form is `invalid var quote` | |
| `#_` | discard the next form | |
| `;` | comment to end of line | |
| `##` | `##Inf` `##-Inf` `##NaN` | |
| `^` | metadata on the next form | data mode: attached to lists, vectors, maps, sets; any other form reads as `(with-meta form m)` with a symbol tag quoted (`:1617`) |
| `) ] }` | `unmatched delimiter c` | |
| `` ` `` `#(` `#"` `#?` `#letter` | named limits (below) | |
| anything else | a token up to whitespace or a terminating macro (`( ) [ ] { } " \ ; @ ` ~ ^`) | `nil` `true` `false`; `:…` keyword; else symbol |

Symbols are not validated (`a/b/c`, `/`, `clojure.core//`, `a:b`, `a#b`,
`a'b` all read). Keywords reject an empty part, a leading or trailing `:`
or `::` inside a part (`hasInvalidKeywordColon`, `:324`); `:/` is the
keyword `/`.

## Numbers

`readNumber` (`:638`) collects the token and tries, in order, Go parsers
whose own syntax decides the result. The cascade is reproduced step by step
because each step's quirks are observable:

| step | parser | findings (native, measured) |
|---|---|---|
| `…N` / `…n` | `big.Int.SetString(s, 10)` | `1N` is a BigInt even when small; `1.5N`, `0x10N` fall through to `invalid number` |
| `…M` / `…m` | `big.Float.Parse(s, 10)` | accepts `p` exponents: `1p3M` is `8.0M` |
| `0x…` (after an optional `-`) | `big.Int.SetString(hex, 16)` | the hex part takes its own sign: `0x-5` is -5, `-0x-5` is 5; `+0x1F` is invalid; past int64 → BigInt, but `-0x8000000000000000` is an Int |
| `0[0-7]…` | `ParseInt(s[1:], 8)` | `017` is 15; `018` and `08` are DECIMAL 18 and 8 (octal fails, decimal wins); octal overflow ends up a decimal BigInt |
| `NrDDD` | `Atoi(N)` in 2..36, `ParseInt(DDD, N)` | both take a sign: `+2r101` 5, `2r-101` -5, `-2r-101` 5; overflow is `invalid number`, never BigInt |
| `N/D` | `ParseInt` both, `big.Rat` | an Int when D divides N (`4/2` is 2, `4/-2` is -2); `1/2` a Ratio; `1/0` invalid; `MinInt64/-1` a BigInt |
| decimal | `ParseInt(s, 10)` | past int64 → BigInt |
| float | `ParseFloat(s, 64)` | underscores between digits are legal: `1_000` is the FLOAT 1000.0; hex floats `0x1p-2`; `1.` and `1.e5` read; overflow (`1e309`, `1.7976931348623159e308`) is `invalid number`; underflow is 0.0 |

Floats: readFloat's syntax check with `underscoreOK`
(`internal/strconv/atof.go:182`, `atoi.go:252`), then `decimal.set` and
`decimal.floatBits` (`atof.go:80`, `:322`) over the same multiprecision
decimal str.lg's formatter ports (800 digits, `trunc` flag, 59-bit shift
chunks). Go's fast paths (exact, Eisel-Lemire, uscale) all return the
correctly rounded double, so the exact slow path is the whole algorithm.
`floatBits` yields a 53-bit mantissa and a binary exponent; the double is
`f64(mant) * 2^(exp-52)`, scaled in exact power-of-two steps (every
intermediate has at most 53 significant bits and an exponent at or above
the result's, so no step rounds). No `f64-from-bits` intrinsic is needed.

## Error messages

Every failure is a `ReaderError` (`errors.go:37`): `Syntax error reading
source at (<read-string>:L:C).\n<msg>`, L and C 1-based and counted in runes
at the moment of failure. Each `Wrap` appends `\n\tcaused by <inner>`
(`errors.AddCause`), so the chain depth is part of the message:
`(1` and `""` carry two `unexpected error` layers over `EOF`, each enclosing
collection adds one. The chain is kept as a vector of layers and joined once
when raised. Static messages, all compared exactly by the test:

| message | site |
|---|---|
| `unexpected error` (wrapping EOF or an inner error) | eatWhitespace `:210`, Read `:263-291`, readToken, readString `:443-448`, readChar `:582`, collections `:762-894` |
| `invalid token: <tok>` | interpretToken `:345-375` |
| `unpaired high surrogate \uXXXX`, `invalid low surrogate \uXXXX`, `unpaired low surrogate \uXXXX` | readString `:479-494` |
| `unknown escape sequence \c` | `:499` |
| `invalid escape sequence \u<digits read>` | readHexEscape `:554`, `:561` |
| `invalid char constant \<tok>` | readChar `:635` |
| `invalid number: <tok>` | readNumber `:750` |
| `map literal must contain even number of forms` | `:847` |
| `duplicate key in map literal: <key.String()>` | `:855` |
| `Duplicate key: <elem>` | readSet `:905` |
| `reading quoted form`, `reading deref form`, `reading unquote prefix`, `reading unquoted form`, `reading quoted var`, `invalid var quote` | `:915-1186` |
| `reading meta` (drops the inner chain), `unsupported meta form` | readMeta `:1620-1683` |
| `reading symbolic value`, `unknown symbolic value: ##<tok>` | `:1705-1720` |
| `reading hash macro`, `invalid hash macro` | `:1727`, `:1737` |
| `unmatched delimiter c` | `:1883` |

Messages that embed a value use `wasm.str/value-string` (Value.String()),
so `duplicate key in map literal: "a"` and `Duplicate key: \a` match too.

## Named limits

Raised catchable (wasm.core/raise) with `lower-wasm: read-string: …`,
not trapped, because the input is user data and xsofy's console catches
read errors. Each names what native would return:

| input | native | why not here |
|---|---|---|
| `1N`, past-int64 integers, hex past int64, `MinInt64/-1` | BigInt | no BigInt box |
| `1/2` | Ratio | no Ratio box |
| `1.5M` | BigDecimal | no BigDecimal box |
| `0x1p-2` | Float | hex floats: rare, need a hex mantissa path (the decimal type only takes decimal digits) |
| `::k`, `::alias/k` (after the validity checks) | `:<current-ns>/k` | needs `*ns*` / the alias table |
| `` `x `` | syntax-quoted form | resolves symbols against `*ns*` |
| `#(…)` | `(fn* [%1] …)` | code, not data |
| `#"re"` | Regex | no Regex box |
| `#?(…)` | the `:lg`/`:default` branch | reader conditionals |
| `#inst`, `#uuid`, `#foo` | Instant/UUID, or the bare value when no reader is registered | tagged literals / `*data-readers*` |
| `^m ;c`, `';c`, … | `(with-meta <VOID> m)`, `(quote <VOID>)` | Go's VOID sentinel is not a value here |

The test admits a limit only when native's answer shows the named thing
(a BigInt in the result, `#?` in the input, …). As of 2026-10-01 the corpus
hits 28 limits in 951 inputs.

## Divergences (known, not tested as matches)

- An empty list read gets position meta like any list. Native stamps it on
  the process-global `EmptyList` singleton (`FormSource.Set` keys by
  pointer, `vm/source.go:278`), so `(meta ())` anywhere returns the last
  read's position: an upstream bug, not reproduced. The test drops
  `:line`/`:column` from empty lists on both sides.
- Position meta lives in the list's meta field (D69), so `conj` keeps it;
  native's FormSource is keyed by the `*List` pointer and a conj'd list has
  none.
- A named limit inside `#_` raises; native reads the discarded form and
  drops it (`#_ 1N 5` is 5 natively).
- `\u-8000000000000000` (a char whose `%x` scan yields MinInt64) is
  rejected; native reads `\u0000` via `rune(hexi)` truncation. Every other
  truncation is reproduced (`က00041` is `\A`, `\u-041` is rune -65).
- Invalid UTF-8 input is decoded exactly as Go does but untested: native lg
  strings cannot be built with invalid bytes from the test.

## Dedupe (proposed, not applied: other rt files are frozen for P3.0)

reader.lg duplicates str.lg's private multiprecision decimal (`dec-trim!`,
`right-shift!`, `left-shift!`, `dec-shift!`, `should-round-up?`) and a
small byte buffer with `encode-rune!`. Making those public in str.lg
(`defn-` to `defn`) lets reader.lg drop ~110 lines. core.lg's
`read-string` stub (core.lg:1005, a trap) should go once reader.lg is in
the load order; until then `tools/twin-manifest.lg` lists both claims.

## Checks

`corpus/intrinsics/reader_test.lg` via `checks/run-intrinsics-native.sh`
(7 deftests, ~11 s under the reference intrinsics on 2026-10-01):

- `edn-corpus`: every line of `corpus/edn/cases.txt` (951 as of
  2026-10-01; regenerate with `lg corpus/edn/gen.lg`): pr-str equal (the
  runtime printer against native's, so map/set order and float digits too),
  metadata of every nested collection equal, or the same error message.
- `floats-round-trip-bits`: the 278 finite lines of
  `corpus/floats/pr-str.expected` read to the same IEEE bits.
- `floats-decimal-sweep`: long decimal strings (17-25 digits, exponents
  -345..334) bit for bit; 100 by default, 1000 with `SLOW=1` (~40 s).
- `argument-errors`, `read-string-star`, `xsofy-call-sites`, `dialect`.

Falsified 2026-10-01: writing `h + 1` for a `\uXXXX` escape turns
`edn-corpus` red with 144 mismatches.
