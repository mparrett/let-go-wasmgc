# checks/env.sh — sourced by every script here. One root, LW_ROOT, holds the
# sibling checkouts and the pinned lg:
#   $LW_ROOT/let-go      let-go checkout containing commit 4e769212
#   $LW_ROOT/xsofy       xsofy checkout (its corpora and the browser lane)
#   $LW_ROOT/legmacs     legmacs checkout
#   $LW_ROOT/lg-bin/lg-4e76921230   native lg built from that commit
# LW_ROOT is found automatically when this repository sits beside let-go/
# (a plain clone next to its siblings) or three levels below it (inside a
# workspace); otherwise set it. Each path can still be overridden on its own
# (LG, LETGO, XSOFY, LEGMACS). Exported so the driver (lw_rt.lg reads
# LETGO) and the row commands in items.tsv see the same values.
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
LG=${LG:-$LW_ROOT/lg-bin/lg-4e76921230}
LETGO=${LETGO:-$LW_ROOT/let-go}
XSOFY=${XSOFY:-$LW_ROOT/xsofy}
LEGMACS=${LEGMACS:-$LW_ROOT/legmacs}
export LW_ROOT LG LETGO XSOFY LEGMACS
unset lw_env_here lw_env_src lw_c
