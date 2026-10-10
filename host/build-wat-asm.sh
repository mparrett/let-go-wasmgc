#!/usr/bin/env bash
# host/build-wat-asm.sh <out.wasm> — build host/wat-asm (wasm-tools' `wat`
# crate behind a four-export ABI, see its lib.rs) for wasm32-unknown-unknown
# and copy the module to <out.wasm>. Needs cargo with that target installed
# (`rustup target add wasm32-unknown-unknown`). The build is cached under
# $LW_WAT_ASM_DIR (default $TMPDIR/lw-wat-asm) by a hash of the crate's files,
# so a repeat costs a copy; the first takes about half a minute.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: build-wat-asm.sh <out.wasm>}
crate=$here/host/wat-asm
command -v cargo >/dev/null || { echo "build-wat-asm: cargo not found" >&2; exit 1; }
rustup target list --installed 2>/dev/null | grep -qx wasm32-unknown-unknown \
  || { echo "build-wat-asm: the wasm32-unknown-unknown target is not installed (rustup target add wasm32-unknown-unknown)" >&2; exit 1; }
key=$(cat "$crate/Cargo.toml" "$crate/Cargo.lock" "$crate/src/lib.rs" | shasum | cut -c1-12)
cache=${LW_WAT_ASM_DIR:-${TMPDIR:-/tmp}/lw-wat-asm}/$key
if [ ! -f "$cache/wat_asm.wasm" ]; then
  mkdir -p "$cache"
  cargo build --quiet --release --locked --target wasm32-unknown-unknown \
    --manifest-path "$crate/Cargo.toml" --target-dir "$cache/target" >"$cache/build.log" 2>&1 \
    || { echo "build-wat-asm: cargo build failed:" >&2; tail -20 "$cache/build.log" >&2; exit 1; }
  command cp "$cache/target/wasm32-unknown-unknown/release/wat_asm.wasm" "$cache/wat_asm.wasm"
fi
mkdir -p "$(dirname "$out")"
command cp "$cache/wat_asm.wasm" "$out"
echo "wat-asm ($key): $(wc -c <"$out" | tr -d ' ') B -> $out" >&2
