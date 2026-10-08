#!/usr/bin/env bash
# --target llvm runner (spike, 2026-10-07): compile a program to LLVM IR, then
# either build it with clang against host/native/lg_rt.c and run the binary,
# or (LW_NATIVE_JIT=1) link the module with the host's bitcode and run it
# under lli. Behaves like lg on stdout and exit status, for checks/oracle.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
prog=${1:?usage: native-run.sh <prog.lg> [args...]}; shift
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
t=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
# LG_ARGS' -source-paths names program library roots, as for checks/wasm-run.sh;
# LW_DRIVER_ARGS adds driver flags (checks/run-tests.sh passes --test etc.)
sp=""; read -r -a lgargs <<<"${LG_ARGS:-}"
for ((i = 0; i < ${#lgargs[@]}; i++)); do [ "${lgargs[$i]}" = -source-paths ] && sp=${lgargs[$((i + 1))]:-}; done
drv=("$LG" -source-paths "$here/src${sp:+:$sp}" "$here/src/driver.lg" --target llvm)
[ -n "$sp" ] && drv+=(-source-paths "$sp")
[ -n "${LW_PROFILE:-}" ] && drv+=(--profile "$LW_PROFILE")
read -r -a dargs <<<"${LW_DRIVER_ARGS:-}"; drv+=(${dargs[@]+"${dargs[@]}"})
if ! "${drv[@]}" "$prog" "$t/m.ll" > "$t/compile.log" 2>&1; then
  cat "$t/compile.log" >&2; exit 1
fi
field() { "$LG" -source-paths "$here/src" "$here/checks/profile-field.lg" "${LW_PROFILE:-host}" "$1"; }
# the fixnum width rt.c boxes with is the profile's (spec decision 8)
fixbits=$(field fixnum-bits) || exit 1
if [ "$(field host)" = bare ]; then
  # a bare board (spec decision 11), LLVM only: llc for the profile's triple,
  # clang and lld to link the board's start.S and link.ld, the bare host and
  # compiler-rt's builtins (checks/build-builtins.sh), then the profile's
  # :run command. Board paths are relative to the repo root.
  lld=${LLD_BIN:-/opt/homebrew/opt/lld/bin}
  triple=$(field triple) cpu=$(field cpu) features=$(field features) board=$(field board)
  read -r -a pcflags <<<"$(field cflags)"; read -r -a run <<<"$(field run)"
  builtins=$("$here/checks/build-builtins.sh" "${LW_PROFILE:-host}")
  heap=$(field heap | sed -E 's/.*:bytes ([0-9]+).*/\1/')
  "$llvm/llc" -O2 -mtriple="$triple" ${cpu:+-mcpu="$cpu"} ${features:+-mattr="$features"} -filetype=obj "$t/m.ll" -o "$t/m.o"
  b=$here/host/native/boards/$board
  "$llvm/clang" --target="$triple" "${pcflags[@]}" -ffreestanding -O2 -w -nostdlib -fuse-ld="$lld/ld.lld" \
    "-DLG_FIXNUM_BITS=$fixbits" "-DLG_HEAP_BYTES=$heap" -T "$b/link.ld" "$b/start.S" \
    "$here/host/native/rt.c" "$here/host/native/bare.c" "$t/m.o" "$builtins" -o "$t/m.elf"
  exec "${run[@]}" "$t/m.elf"
fi
cflags=(-O2 -w "-DLG_FIXNUM_BITS=$fixbits")
host_c=("$here/host/native/rt.c" "$here/host/native/posix.c")
if [ -n "${LW_NATIVE_JIT:-}" ]; then
  for c in "${host_c[@]}"; do "$llvm/clang" "${cflags[@]}" -c -emit-llvm "$c" -o "$t/$(basename "$c" .c).bc"; done
  "$llvm/llvm-link" "$t/m.ll" "$t/rt.bc" "$t/posix.bc" -o "$t/all.bc"
  exec "$llvm/lli" -O2 "$t/all.bc" "$prog" "$@"
fi
"$llvm/clang" "${cflags[@]}" "${host_c[@]}" "$t/m.ll" -o "$t/m"
"$t/m" "$prog" "$@"
