#!/usr/bin/env bash
# checks/self-compiled-run.sh [program...] — row P12.5: a self-compiled
# program runs (D212). The P12.4 module (the backend carried as a program,
# with the env.assemble seam: checks/self-compile-module.sh builds it exactly
# as checks/self-compile-assemble.sh does, from P12.4's fixture) compiles each
# program INSIDE the module under node: the carried driver/compile-text reads
# the program through the host's file import, hands the WAT to env.assemble,
# and src/run.mjs keeps the binary (LW_ASSEMBLE_OUT). Then node runs that
# binary with the normal runner, and checks/oracle.sh compares it with native
# lg (stdout, exit class, first error line): WASM_RUN is this script's
# --run mode, which runs the kept binary in place of compiling.
#
# One line per program: MATCH / MISMATCH (the oracle's reason) / COMPILE-FAIL
# (the module's first error line), with the in-module compile seconds (the
# fixture's `time` around compile-text), the native driver's compile seconds
# for the same program and options (`driver.lg --no-rtlib`, same LW_* env),
# the result's run seconds, the compiling node process's peak RSS, and
# whether the carried WAT equals native's (`wat=` same / DIFF; not gating: a
# difference is a finding about the carried backend). Then `n/total MATCH`;
# exit 0 iff all MATCH.
#
# Every program is compiled --no-rtlib (P12.4's reason: the rtlib key hashes
# the lg binary through os/sh, which a module cannot run), so an eval program
# builds the whole runtime library inside the module. Default list, in order:
# corpus/scalar/ref.lg, fib.clj, tak.clj, loop-recur.clj, os-args.lg, then
# corpus/eval/special/basic.lg (the one eval program). Arguments replace the
# list. LW_SCR_TIMEOUT caps each in-module compile (default 1800 s: past it
# the program is COMPILE-FAIL "timeout").
#
# Measured 2026-10-09 07:24-07:38 at d3aa439 (macOS arm64, other sessions'
# load 2-4): module 4,228,599 bytes, built in 282 s from a warm rtlib (the
# first build after the evaluator's dotimes change, a new rtlib key, took
# 317 s; P12.4's 3,972,833 grew by the builtin names entries, D212); the
# whole run peaked at 2.5 GB RSS (the module build). Per program:
#
#   program         in module  native  run    node peak  result     WAT
#   ref.lg            23.7 s     9 s   0.2 s  0.48 GB    MATCH      2 type decls
#   fib.clj           17.0 s     0 s   0.1 s  0.44 GB    MATCH      same
#   tak.clj           18.6 s     1 s   0.1 s  0.44 GB    MATCH      same
#   loop-recur.clj    15.6 s     1 s   0.1 s  0.44 GB    MATCH      same
#   os-args.lg        78.4 s    11 s   0.1 s  0.60 GB    MATCH      2 type decls
#   basic.lg (eval)  137.8 s    58 s   0.1 s  1.07 GB    MISMATCH   3.1 MB vs 6.3 MB
#
# "2 type decls": native's text declares $Env_b and $Env_bb, the closure
# environments of core/keep (rt/wasm/emit.lg calls it), which native lowers
# and then shakes out; the carried compile never registers them. Every
# function is the same. basic.lg: the carried compile stubs wasm.eval/comp*
# and core-table* ("runtime call arity {:var #'lwx.lw-ext/list-n :argc 1}"),
# so every eval prints that error; `(println (list 1 2 3 4 5))` reproduces it
# in the module, native prints (1 2 3 4 5). Its 137.8 s is a lower bound: the
# stubs cut what the compile reaches (half native's text).
#
# Env: LG, LETGO (env.sh), LW_SELF_COMPILE_CACHE (the module build's rtlib
# dir), LW_SCR_TIMEOUT, KEEP=1, LW_SCR_REUSE=<a kept dir> (skip the module
# build; for re-running programs and the falsifications).
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/checks/env.sh"
export LG
if [ "${1:-}" = --run ]; then
  # oracle.sh's WASM_RUN: `--run <binary> <program> args..`; the program was
  # compiled already, so only its arguments matter (os/args as wasm-run.sh)
  bin=$2; shift 2
  exec node "$root/src/run.mjs" "$bin" "$@"
fi
fixture=$root/checks/fixtures/self-compile-assemble/main.lg
if [ $# -gt 0 ]; then programs=("$@"); else
  programs=("$root/corpus/scalar/ref.lg" "$root/corpus/scalar/fib.clj" "$root/corpus/scalar/tak.clj"
            "$root/corpus/scalar/loop-recur.clj" "$root/corpus/scalar/os-args.lg"
            "$root/corpus/eval/special/basic.lg")
fi
cap=${LW_SCR_TIMEOUT:-1800}
if [ -n "${LW_SCR_REUSE:-}" ]; then
  # a KEEP=1 run's directory: its module is reused, the rest redone
  t=$LW_SCR_REUSE
else
  t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
fi
. "$root/checks/self-compile-module.sh"
sc_setup || exit 1
if [ -n "${LW_SCR_REUSE:-}" ] && [ -f "$t/m.wasm" ]; then
  size=$(wc -c <"$t/m.wasm" | tr -d ' '); build="(reused) 0"
else
  sc_build "$fixture" || { echo "MISMATCH self-compiled-run: the module did not build"; exit 1; }
fi
echo "module built (${size} bytes; ${build}s)"
pass=0 i=0
for p in "${programs[@]}"; do
  i=$((i + 1)); name=$(basename "$p"); out=$t/p$i.wasm
  # the native driver on the same program and options: its time and its text
  s0=$(date +%s)
  if "$LG" -source-paths "$root/src" "$root/src/driver.lg" --no-rtlib "$p" "$t/native$i.wat" >"$t/native$i.log" 2>&1; then
    ntime="$(( $(date +%s) - s0 ))s"
  else
    ntime="FAIL"
  fi
  /usr/bin/time -l timeout "$cap" env LW_RT_SNAPSHOT="$t/rt-snapshot.edn" LW_ASSEMBLE_IN="$p" LW_ASSEMBLE_OUT="$out" \
    node "$root/src/run.mjs" "$t/m.wasm" "$fixture" >"$t/c$i.out" 2>"$t/c$i.err"
  rc=$?
  rss=$(awk '/maximum resident set size/ {printf "%.2fGB", $1 / 1073741824}' "$t/c$i.err")
  ctime=$(awk '/^"?Elapsed time:/ {gsub(/"/, ""); printf "%.1fs", $3 / 1000}' "$t/c$i.out")
  if [ $rc -ne 0 ] || [ ! -f "$out" ]; then
    why=$( { [ $rc -eq 124 ] && echo "timeout after ${cap}s"; grep -v '^\s*at ' "$t/c$i.err" | grep -v 'resident\|^ *[0-9]' | grep -v '^\s*$'; } | head -1)
    echo "COMPILE-FAIL $name (exit $rc; native ${ntime}; peak ${rss}): ${why:-no binary kept}"
    continue
  fi
  wat=DIFF; cmp -s "$out.wat" "$t/native$i.wat" && wat=same
  s0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  node "$root/src/run.mjs" "$out" "$p" >/dev/null 2>&1
  run=$(perl -MTime::HiRes=time -e "printf '%.1fs', time - $s0")
  verdict=$(WASM_RUN="$0 --run $out" "$root/checks/oracle.sh" "$p" 2>&1)
  line="$name (compile ${ctime:-?} in module, native ${ntime}; run ${run}; peak ${rss}; wat=${wat})"
  if [ "$verdict" = MATCH ]; then
    pass=$((pass + 1)); echo "MATCH $line"
  else
    echo "MISMATCH $line: $(echo "$verdict" | head -1)"; echo "$verdict" | tail -n +2 | head -4 | sed 's/^/  /'
  fi
done
echo "$pass/${#programs[@]} MATCH (module ${size} bytes, build ${build}s)"
[ "$pass" -eq "${#programs[@]}" ]
