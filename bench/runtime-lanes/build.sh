#!/usr/bin/env bash
# Build each progs/*.clj once per target (linear, gc) into $OUT/mods, and as a
# gogen AOT binary into $OUT/aot. Skips outputs that already exist.
# Env: OUT (default $TMPDIR/runtime-lanes), LGV (required: lg for `lg compile`).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); W=${LW_SRC:-$here/../..}
OUT=${OUT:-${TMPDIR:-/tmp}/runtime-lanes}
LGV=${LGV:?set LGV to the lg binary for the vm lane and lg compile (the 2026-10-05 runs used dbaf59cb)}
. "$W/checks/env.sh"
mkdir -p "$OUT/mods" "$OUT/aot"
for f in "$here"/progs/*.clj; do
  n=$(basename "$f" .clj)
  for tgt in linear gc; do
    out=$OUT/mods/$n.$tgt; [ -f "$out.wasm" ] && continue
    s=$(date +%s)
    args=(); [ $tgt = linear ] && args=(--target linear)
    if "$LG" -source-paths "$W/src" "$W/src/driver.lg" ${args[@]+"${args[@]}"} "$f" "$out.wat" >"$out.log" 2>&1 \
       && wasm-tools parse "$out.wat" -o "$out.wasm"; then
      echo "$n $tgt ok $(( $(date +%s)-s ))s $(stat -f %z "$out.wasm")B"
    else echo "$n $tgt FAIL $(( $(date +%s)-s ))s (see $out.log)"; fi
  done
  # lg compile needs a -main: wrap the program's top-level println
  [ -x "$OUT/aot/$n" ] && continue
  { sed 's/^(println/(defn -main [\& _] (println/' "$f"; echo ')'; } > "$OUT/aot/$n.lg"
  (cd "$OUT/aot" && "$LGV" compile -o "$n" "$n.lg" >"$n.log" 2>&1) && echo "$n aot ok" || echo "$n aot FAIL (see $OUT/aot/$n.log)"
done
