#!/usr/bin/env bash
# checks/emit-native.sh [program...] — row P10.1: stage 3a of
# docs/SELF-HOST-SPEC.md. The evaluator's second output (rt/wasm/emit.lg)
# compiles each fitting program's fns to a standalone wasm module under
# stock lg; node runs it; the result must equal native lg's.
#
# Programs: corpus/scalar/*, corpus/opmatrix/*.lg, corpus/typed/*.lg and
# corpus/emit/*.lg, the programs this path's own review found (or the ones
# named). A program FITS when its top level is only
#   - defn / defn- / fn forms (the module: every fn in it),
#   - (println item..), item a string, a scalar literal, or an expression,
#   - the op-matrix row (try (println item..) (catch Exception e
#     (println "text".. (ex-message e)))),
#   - any other expression, run for its effect (its value discarded),
# and wasm.emit accepts every form. An expression item becomes a call of an
# export with boxed arguments: (f lit..) of the program's own fn calls f's
# export; (op lit..) of anything else calls a wrapper the driver adds,
# (defn |lw op op/n| [p..] (op p..)); any other expression a thunk
# (defn |lw t K| [] expr). The driver (below, under stock lg) writes the
# module and a run plan (checks/emit-run.mjs's header); every other program
# is listed as SKIP with the reason (the driver's, or wasm.emit's named
# error), as is a program its directory's SKIP file lists.
#
# Each fitting program then goes through checks/oracle.sh (stdout, exit
# class, first error line) with WASM_RUN = this script's --run side:
# `wasm-tools validate` on the bytes, then node checks/emit-run.mjs.
# Prints MATCH/MISMATCH/SKIP per program, the skip list, "n/fit MATCH
# (total programs)" and the wall time. Exit 0 iff every fitting program
# MATCHes; 2 if node or wasm-tools is missing. Env: LG (env.sh).
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/checks/env.sh"
command -v node >/dev/null || { echo "node not on PATH"; exit 2; }
command -v wasm-tools >/dev/null || { echo "wasm-tools not on PATH"; exit 2; }

# The emit side, called by oracle.sh as WASM_RUN: $0 --run <program>, with
# EMIT_OUT naming the directory the driver wrote for that program.
if [ "${1:-}" = --run ]; then
  d=${EMIT_OUT:?EMIT_OUT unset}
  xxd -r -p "$d/m.hex" "$d/m.wasm"
  if ! v=$(wasm-tools validate "$d/m.wasm" 2>&1); then
    echo "error: wasm-tools validate: $(printf '%s' "$v" | head -1)" >&2; exit 3
  fi
  exec node "$root/checks/emit-run.mjs" "$d/m.wasm" "$d/plan.json"
fi

cd "$root"
t0=$(date +%s)
t=$(mktemp -d "${TMPDIR:-/tmp}/emit-native.XXXXXX"); trap 'rm -rf "$t"' EXIT

if [ $# -gt 0 ]; then progs=("$@"); else
  progs=()
  while IFS= read -r f; do progs+=("$f"); done < <(
    { find corpus/scalar -maxdepth 1 -type f \( -name '*.lg' -o -name '*.clj' \)
      find corpus/opmatrix corpus/typed corpus/emit -maxdepth 1 -type f -name '*.lg'; } | LC_ALL=C sort)
fi

# The driver: one stock-lg process reads every program, classifies it and,
# for a fitting one, writes <out>/<i>/m.hex and plan.json; prints one
# "i FIT" or "i SKIP reason" line per program.
cat >"$t/driver.lg" <<'EOF'
(require 'wasm.eval-native)
(require 'wasm.emit)
(require '[clojure.string :as string])

(def hexd "0123456789abcdef")
(defn hex [bs] (apply str (mapcat (fn [b] [(nth hexd (quot b 16)) (nth hexd (rem b 16))]) bs)))

(defn jstr [s] (str "\"" (-> s (string/replace "\\" "\\\\") (string/replace "\"" "\\\"") (string/replace "\n" "\\n")) "\""))
(defn json [x]
  (cond (string? x) (jstr x)
        (map? x) (str "{" (string/join "," (map (fn [[k v]] (str (jstr (name k)) ":" (json v))) x)) "}")
        (sequential? x) (str "[" (string/join "," (map json x)) "]")
        (nil? x) "null"
        :else (str x)))

(defn lit? [x] (or (nil? x) (true? x) (false? x) (int? x) (float? x)))
(defn arg [x]
  (cond (nil? x) {:nil true}
        (or (true? x) (false? x)) {:b x}
        (int? x) {:i (str x)}
        (not= x x) {:f "NaN"}
        (> x 1.7976931348623157e308) {:f "Inf"}
        (< x -1.7976931348623157e308) {:f "-Inf"}
        (and (= x 0.0) (< (/ 1.0 x) 0.0)) {:f "-0"}
        :else {:f (str x)}))

(defn skip [why] (throw (ex-info why {:skip true})))

(defn plan-program [forms]
  (let [names (set (keep (fn [f] (when (and (seq? f) (#{'defn 'defn-} (first f))) (str (second f)))) forms))
        extra (atom []) ops (atom #{}) nthunk (atom 0)
        item (fn [e]
               (cond (string? e) {:s e}
                     (lit? e) {:v (arg e)}
                     (and (seq? e) (symbol? (first e)) (every? lit? (rest e)))
                     (let [h (first e) n (count (rest e))]
                       (if (contains? names (str h))
                         {:call (str h) :args (mapv arg (rest e))}
                         (let [nm (str "lw op " h "/" n) ps (mapv (fn [i] (symbol (str "p" i))) (range n))]
                           (when-not (contains? @ops nm)
                             (swap! ops conj nm)
                             (swap! extra conj (list 'defn (symbol nm) ps (cons h ps))))
                           {:call nm :args (mapv arg (rest e))})))
                     :else (let [nm (str "lw t " (swap! nthunk inc))]
                             (swap! extra conj (list 'defn (symbol nm) [] e))
                             {:call nm :args []})))
        println? (fn [f] (and (seq? f) (= 'println (first f))))
        steps (reduce
               (fn [acc f]
                 (cond (and (seq? f) (#{'defn 'defn- 'fn} (first f))) acc
                       (println? f) (conj acc {:print (mapv item (rest f))})
                       (and (seq? f) (= 'try (first f)) (= 3 (count f)) (println? (nth f 1)))
                       (let [c (nth f 2)]
                         (when-not (and (seq? c) (= 'catch (first c)) (= 4 (count c)) (println? (nth c 3)))
                           (skip "a try other than the op-matrix row"))
                         (let [e (nth c 2)
                               citems (mapv (fn [x] (cond (string? x) {:s x}
                                                          (= x (list 'ex-message e)) {:err true}
                                                          :else (skip "a catch printing more than text and (ex-message e)")))
                                            (rest (nth c 3)))]
                           (conj acc {:print (mapv item (rest (nth f 1))) :catch citems})))
                       :else (conj acc {:print [(item f)] :discard true})))
               [] forms)
        mod-forms (concat (filter (fn [f] (and (seq? f) (#{'defn 'defn- 'fn} (first f)))) forms) @extra)]
    {:bytes (wasm.eval/emit-module mod-forms) :steps steps}))

(let [[out & progs] *command-line-args*]
  (doseq [[i p] (map-indexed vector progs)]
    (let [r (try (let [forms (read-string (str "[" (slurp p) "\n]"))
                       t0 (System/nanoTime) pl (plan-program forms) ms (quot (- (System/nanoTime) t0) 1000000)
                       d (str out "/" i)]
                   (os/sh "mkdir" "-p" d)
                   (spit (str d "/m.hex") (hex (:bytes pl)))
                   (spit (str d "/plan.json") (json {:steps (:steps pl)}))
                   (str "FIT " (count (:bytes pl)) " bytes, emitted in " ms " ms"))
                 (catch Exception e (str "SKIP " (ex-message e))))]
      (println i r))))
EOF
"$LG" -source-paths "$root/rt" "$t/driver.lg" "$t/out" "${progs[@]}" >"$t/classes.txt" 2>"$t/driver.err" || {
  echo "driver failed:"; cat "$t/driver.err" "$t/classes.txt" | head -20; exit 1; }

# A directory's SKIP file (corpus/opmatrix/SKIP: the `/` programs whose rows
# need ratios and bigints, D15) skips here too, with its comment as reason.
listed() {
  local sf; sf=$(dirname "$1")/SKIP
  # a bare name skips the program in every check; "<row> name" in this row only
  [ -f "$sf" ] && awk -v b="$(basename "$1")" -v r=P10.1 '/^#/ {c=$0; next} $1==b || ($1==r && $2==b) {sub(/^# */, "", c); print c; found=1} END {exit !found}' "$sf"
}

n=${#progs[@]} fit=0 match=0 bad=0 skips=()
for ((i=0; i<n; i++)); do
  f=${progs[$i]}
  c=$(grep "^$i " "$t/classes.txt" | head -1 | cut -d' ' -f2-)
  if why=$(listed "$f"); then c="SKIP $(dirname "$f")/SKIP: $why"; fi
  case $c in
    FIT*)
      fit=$((fit+1))
      o=$(EMIT_OUT="$t/out/$i" WASM_RUN="$root/checks/emit-native.sh --run" checks/oracle.sh "$f" 2>&1); rc=$?
      if [ $rc -eq 0 ]; then match=$((match+1)); echo "MATCH $f (${c#FIT })"
      else bad=1; echo "MISMATCH $f: $(printf '%s' "$o" | head -1)"; printf '%s\n' "$o" | sed -n '2,6p' | sed 's/^/    /'; fi ;;
    SKIP*) skips+=("$f: ${c#SKIP }"); echo "SKIP $f" ;;
    *) bad=1; echo "NO-RESULT $f" ;;
  esac
done
echo "skipped (${#skips[@]}):"
for s in "${skips[@]+"${skips[@]}"}"; do echo "  $s"; done
echo "$match/$fit MATCH ($n programs, ${#skips[@]} skipped)"
echo "emit-native: wall $(( $(date +%s) - t0 ))s"
[ $bad = 0 ]
