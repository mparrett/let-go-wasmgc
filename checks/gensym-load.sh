#!/usr/bin/env bash
# checks/gensym-load.sh — P9.1 (D196, the D188/D192 rule). Loading the driver
# must not change how many gensyms are taken before a program's macros expand.
# Destructuring (one per binding) and `for` (four) in src/ take gensyms when
# the file loads; #() does not on the pinned lg (it reads as (fn* [%1] ..)).
# The counter carries into the program's expansions and renumbers locals in
# every emitted module (D174, D188, the PR #1 legmacs byte shift in D192)
# without changing behaviour. The 20 small programs of the GC byte guard can
# miss that; this row catches it in a few seconds.
#
# Compiles checks/fixtures/gensym-probe.lg with --no-rt (load-time effects
# only; no runtime library built) and compares the counter its macro saw with
# EXPECT. A src/ change that moves it either keeps byte identity by avoiding
# the gensym, or records the new value here and says in its DECISIONS entry
# that local numbering moved (checked with "differs only in local numbering"
# plus gate 1).
# Inputs: src/, rt/ (--no-rt skips building the runtime library but the loader
# still reads rt/wasm/*.lg in README order before the probe expands, so a
# destructuring defn added to the runtime moves the count too), the fixture,
# checks/env.sh. The probe runs under the default loading configuration:
# LW_RUNTIME_COMPILE, LW_EXPORT_RT and LW_RT_DIR are cleared, since the
# self-host rows (D193) load two more files and take 22 more gensyms, and a
# caller exporting them must not read as a src/ regression.
set -uo pipefail
. "$(dirname "$0")/env.sh"
cd "$(dirname "$0")/.."
EXPECT=1133   # 1130 at let-go ff1e6dac; the e9789b7d lg takes three more at load (D217)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
env -u LW_RUNTIME_COMPILE -u LW_EXPORT_RT -u LW_RT_DIR \
  "$LG" -source-paths "$PWD/src" src/driver.lg --no-rt checks/fixtures/gensym-probe.lg "$t/p.wat" >"$t/log" 2>&1 \
  || { echo "compile failed"; tail -5 "$t/log"; exit 1; }
# the string's data segment is named after its hex bytes: s_<hex of "lw-gensym-probe-">...
hex=$(grep -o 's_6c772d67656e73796d2d70726f62652d[0-9a-f]*' "$t/p.wat" | head -1)
[ -n "$hex" ] || { echo "probe string not found in the module"; exit 1; }
got=$(printf '%s' "${hex#s_6c772d67656e73796d2d70726f62652d}" | sed 's/../\\x&/g')
got=$(printf "$got")
if [ "$got" = "$EXPECT" ]; then
  echo "OK gensym counter after load: $got"
else
  echo "MOVED gensym counter after load: $got (recorded $EXPECT)"
  echo "a src/ or rt/ change takes a different number of gensyms at load; see the header"
  exit 1
fi
