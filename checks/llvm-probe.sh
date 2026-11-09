#!/usr/bin/env bash
# checks/llvm-probe.sh [--bare] — the llvm lane's one discovery step, as
# checks/browser-probe.mjs is the browser lanes': a row that compiles for
# --target llvm runs it first (`checks/llvm-probe.sh && …`).
#
# Exit 0 when the toolchain the lane needs is here: clang in $LLVM_BIN
# (default Homebrew's llvm), which every llvm compile asks for the data
# layout and the host lane links with; with --bare also ld.lld in $LLD_BIN
# (default Homebrew's lld) and qemu-system-arm on PATH, for the bare boards.
# Otherwise it prints `SKIP <what is missing>` and exits 2, so the gate
# reports the row as skipped; with LW_REQUIRE_LLVM=1 it prints FAIL and
# exits 1 instead, for a machine that must run the lane.
set -uo pipefail
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
lld=${LLD_BIN:-/opt/homebrew/opt/lld/bin}
missing=()
[ -x "$llvm/clang" ] || missing+=("clang in $llvm (set LLVM_BIN)")
if [ "${1:-}" = --bare ]; then
  [ -x "$lld/ld.lld" ] || missing+=("ld.lld in $lld (set LLD_BIN)")
  command -v qemu-system-arm >/dev/null || missing+=("qemu-system-arm on PATH")
fi
[ ${#missing[@]} -eq 0 ] && exit 0
why=$(printf '%s; ' "${missing[@]}"); why=${why%; }
if [ "${LW_REQUIRE_LLVM:-}" = 1 ]; then echo "FAIL (LW_REQUIRE_LLVM is set: no $why)"; exit 1; fi
echo "SKIP no $why"
exit 2
