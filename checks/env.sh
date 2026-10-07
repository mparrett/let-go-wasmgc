# checks/env.sh — sourced by every script here. One root, LW_ROOT, holds the
# sibling checkouts and the pinned lg:
#   $LW_ROOT/let-go      let-go checkout containing commit ff1e6da
#   $LW_ROOT/xsofy       xsofy checkout (its corpora and the browser lane)
#   $LW_ROOT/legmacs     legmacs checkout
#   $LW_ROOT/lg-bin/lg-ff1e6dac76   native lg built from that commit
# LW_ROOT is found automatically when this repository sits beside let-go/
# (a plain clone next to its siblings) or three levels below it (inside a
# workspace); otherwise set it. Each path can still be overridden on its own
# (LG, LETGO, XSOFY, LEGMACS, WASM_OPT, WASM_MERGE). Exported so the driver
# (lw_rt.lg reads LETGO) and the row commands in items.tsv see the same values.
# Works when sourced from bash (the scripts) and from an interactive zsh.
if [ -n "${BASH_SOURCE:-}" ]; then lw_env_src=${BASH_SOURCE[0]}; else eval 'lw_env_src=${(%):-%x}'; fi
lw_env_here=$(cd "$(dirname "$lw_env_src")/.." && pwd)
if [ -z "${LW_ROOT:-}" ]; then
  # a root must hold both let-go/ and lg-bin/: a workspace that only symlinks
  # let-go/ beside this tree is not it.
  for lw_c in "$lw_env_here/.." "$lw_env_here/../../.."; do
    if [ -d "$lw_c/let-go" ] && [ -d "$lw_c/lg-bin" ]; then LW_ROOT=$(cd "$lw_c" && pwd); break; fi
  done
fi
: "${LW_ROOT:?set LW_ROOT to the directory holding let-go/, xsofy/, legmacs/ and lg-bin/ (see checks/env.sh)}"
LG=${LG:-$LW_ROOT/lg-bin/lg-ff1e6dac76}
LETGO=${LETGO:-$LW_ROOT/let-go}
XSOFY=${XSOFY:-$LW_ROOT/xsofy}
LEGMACS=${LEGMACS:-$LW_ROOT/legmacs}
# binaryen: the Homebrew install when present, else whatever is on PATH.
# Override with WASM_OPT / WASM_MERGE.
lw_brew=/opt/homebrew/opt/binaryen/bin
WASM_OPT=${WASM_OPT:-$( [ -x "$lw_brew/wasm-opt" ] && echo "$lw_brew/wasm-opt" || command -v wasm-opt || echo wasm-opt)}
WASM_MERGE=${WASM_MERGE:-$( [ -x "$lw_brew/wasm-merge" ] && echo "$lw_brew/wasm-merge" || command -v wasm-merge || echo wasm-merge)}
export LW_ROOT LG LETGO XSOFY LEGMACS WASM_OPT WASM_MERGE
unset lw_env_here lw_env_src lw_c lw_brew
