#!/usr/bin/env bash
# checks/wasmbin-roundtrip.sh [--wat-dir DIR] — row P10.0: the lg wasm
# binary encoder (rt/wasm/wasmbin.lg) against wasm-tools on real modules.
#
# For every program in corpus/scalar/ and corpus/eval/*/ (corpus/eval/
# program/multi/ with -source-paths .../multi/lib; lib/ itself is not a
# program), the backend's driver compiles it to WAT as run-corpus.sh does
# (one rtlib build first, serially, then LW_PAR programs at once through
# checks/sem.sh; LW_RTLIB_DIR is honoured). Then, under stock lg,
# rt/wasm/watread.lg reads that WAT into the encoder's section model and
# rt/wasm/wasmbin.lg encodes it; the bytes must equal `wasm-tools parse` of
# the same WAT exactly (no normalisation: the name section, the implicit
# function types and the data count are reproduced, watread.lg's header).
# After the corpus scan, two larger programs run through the same path:
# checks/fixtures/warm-gensym/main.lg (-source-paths its lib/, the P9.2
# fixture) and legmacs ($LEGMACS/main.lg, -source-paths $LEGMACS, as
# host/build-legmacs-module.sh compiles it; LEGMACS defaults to
# $LW_ROOT/legmacs, env.sh). legmacs is a 12.5 MB WAT (2026-10-07), ~11 s to
# encode and ~0.8 GB RSS, and is last so the corpus results print first. With
# no $LEGMACS directory it prints "SKIP legmacs (no LEGMACS checkout)" and is
# not counted: the total is the programs that ran (the public CI has no
# legmacs checkout).
# Prints MATCH/MISMATCH per program (a mismatch with the first differing
# byte offset), the opnames the modules use against the encoder's table
# (they must be the same set: the table covers exactly the corpus's
# opcodes), "n/total MATCH" and the wall time. Exit 0 iff every program
# MATCHes and the sets agree; 2 if wasm-tools is missing.
#
#   --wat-dir DIR  skip the compile: take DIR/<program path minus extension>.wat
#                  (e.g. DIR/corpus/scalar/fib.wat), as a capture left them;
#                  the fixture is DIR/checks/fixtures/warm-gensym/main.wat and
#                  legmacs is DIR/legmacs/main.wat.
#
# Env: LG, LETGO (env.sh), LW_PAR (default 3), LW_RTLIB_DIR.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/checks/env.sh"
export LG
watdir=""
while [ $# -gt 0 ]; do
  case $1 in
    --wat-dir) watdir=$(cd "${2:?--wat-dir needs a directory}" && pwd) || exit 2; shift 2 ;;
    *) echo "usage: $0 [--wat-dir DIR]" >&2; exit 2 ;;
  esac
done
command -v wasm-tools >/dev/null || { echo "wasm-tools not on PATH" >&2; exit 2; }
par=${LW_PAR:-3}
case $par in ''|*[!0-9]*|0) echo "LW_PAR must be a positive integer (got '$par')" >&2; exit 2;; esac
cd "$root"
t0=$(date +%s)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export t root watdir

# the stock-lg side: WAT -> model -> bytes (hex), and the opnames it used
cat >"$t/encode.lg" <<'EOF'
(require '[wasm.watread :as wr] '[wasm.wasmbin :as wb] '[clojure.string :as string])
(let [[wat hex ops] *command-line-args*]
  (if (= wat "--table")
    (println (string/join "\n" (sort (map name (wb/opnames)))))
    (let [m (wr/module-model (slurp wat))
          exprs (concat (map :body (:code m)) (map :init (:globals m))
                        (keep #(:offset (:mode %)) (:elems m)) (keep #(:offset (:mode %)) (:data m)))]
      (spit hex (wr/bytes->hex (wb/encode-module m)))
      (spit ops (apply str (map #(str % "\n") (sort (set (map #(name (first %)) (apply concat exprs))))))))))
EOF

progs=()
while IFS= read -r f; do progs+=("$f"); done < <(
  { find corpus/scalar -maxdepth 1 -type f \( -name '*.lg' -o -name '*.clj' \)
    find corpus/eval -path '*/lib/*' -prune -o -type f -name '*.lg' -print; } | LC_ALL=C sort)
# Each program is label:entry:source-path ("-" for none). Corpus labels are
# their paths; legmacs' label is not its checkout path, which is machine-specific.
specs=()
for f in "${progs[@]}"; do
  case $f in corpus/eval/program/multi/*) specs+=("$f:$f:corpus/eval/program/multi/lib") ;; *) specs+=("$f:$f:-") ;; esac
done
specs+=("checks/fixtures/warm-gensym/main.lg:checks/fixtures/warm-gensym/main.lg:checks/fixtures/warm-gensym/lib")
skip=""
if [ -d "$LEGMACS" ]; then specs+=("legmacs/main.lg:$LEGMACS/main.lg:$LEGMACS")
else skip="SKIP legmacs (no LEGMACS checkout)"; fi

# One program (spec label:entry:source-path) -> $t/<i>.line, $t/<i>.ops;
# $t/<i>.done last.
one() {
  local i=$1 spec=$2 w sp f label wat ms0 n
  w=$t/$i   # not in the local line above: its words expand before i is assigned
  mkdir -p "$w"
  label=${spec%%:*}; spec=${spec#*:}; f=${spec%%:*}; sp=${spec#*:}
  [ "$sp" = - ] && sp=""
  if [ -n "$watdir" ]; then wat=$watdir/${label%.*}.wat
  else
    wat=$w/m.wat
    if [ -n "$sp" ]; then "$LG" -source-paths "src:$sp" src/driver.lg -source-paths "$sp" "$f" "$wat" >"$w/c.log" 2>&1
    else "$LG" -source-paths src src/driver.lg "$f" "$wat" >"$w/c.log" 2>&1; fi
  fi
  if [ ! -s "$wat" ]; then echo "MISMATCH $label: no WAT ($(tail -1 "$w/c.log" 2>/dev/null))" >"$t/$i.line"; : >"$t/$i.done"; return; fi
  ms0=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
  if ! "$LG" -source-paths rt "$t/encode.lg" "$wat" "$w/mine.hex" "$t/$i.ops" >"$w/e.log" 2>&1; then
    echo "MISMATCH $label: encoder failed: $(grep -m1 . "$w/e.log" | cut -c1-200)" >"$t/$i.line"; : >"$t/$i.done"; return
  fi
  n=$(( $(perl -MTime::HiRes=time -e 'printf "%d", time*1000') - ms0 ))
  if ! wasm-tools parse "$wat" -o "$w/ref.wasm" 2>"$w/p.log"; then
    echo "MISMATCH $label: wasm-tools parse failed: $(head -1 "$w/p.log")" >"$t/$i.line"; : >"$t/$i.done"; return
  fi
  od -An -v -tx1 "$w/ref.wasm" | tr -d ' \n' >"$w/ref.hex"
  if cmp -s "$w/ref.hex" "$w/mine.hex"; then
    echo "MATCH $label ($(( $(wc -c <"$w/ref.hex") / 2 )) bytes, ${n} ms)" >"$t/$i.line"
  else
    local off; off=$(cmp "$w/ref.hex" "$w/mine.hex" 2>&1 | sed -nE 's/.*char ([0-9]+).*/\1/p')
    echo "MISMATCH $label: bytes differ at offset $(( (${off:-1} - 1) / 2 )) (wasm-tools $(( $(wc -c <"$w/ref.hex") / 2 )) bytes, encoder $(( $(wc -c <"$w/mine.hex") / 2 )))" >"$t/$i.line"
  fi
  : >"$t/$i.done"
}
export -f one

if [ -z "$watdir" ]; then
  # build the rtlib once before fanning out (run-corpus.sh's rtlib_warm)
  "$root/checks/sem.sh" "$LG" -source-paths src src/driver.lg corpus/scalar/fib.clj "$t/warm.wat" >"$t/warm.log" 2>&1 \
    || { echo "warm compile failed: $(tail -1 "$t/warm.log")" >&2; exit 1; }
fi
for ((i=0; i<${#specs[@]}; i++)); do printf '%s\0%s\0' "$i" "${specs[$i]}"; done \
  | xargs -0 -n 2 -P "$par" "$root/checks/sem.sh" bash -c 'one "$1" "$2"' _

match=0 bad=0
for ((i=0; i<${#specs[@]}; i++)); do
  if [ -e "$t/$i.done" ]; then cat "$t/$i.line"; else echo "MISSING-RESULT ${specs[$i]%%:*}"; fi
  grep -q '^MATCH ' "$t/$i.line" 2>/dev/null && match=$((match+1)) || bad=1
done
[ -z "$skip" ] || echo "$skip"
cat "$t"/*.ops 2>/dev/null | sort -u >"$t/used.txt"
"$LG" -source-paths rt "$t/encode.lg" --table >"$t/table.txt"
echo "opnames: $(wc -l <"$t/used.txt" | tr -d ' ') used by the modules, $(wc -l <"$t/table.txt" | tr -d ' ') in the encoder's table"
if ! cmp -s "$t/used.txt" "$t/table.txt"; then
  bad=1
  comm -23 "$t/used.txt" "$t/table.txt" | sed 's/^/  used, not in the table: /'
  comm -13 "$t/used.txt" "$t/table.txt" | sed 's/^/  in the table, used by no module: /'
fi
echo "$match/${#specs[@]} MATCH"
echo "wasmbin-roundtrip: wall $(( $(date +%s) - t0 ))s"
[ $bad = 0 ]
