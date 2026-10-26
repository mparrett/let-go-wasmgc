#!/usr/bin/env bash
# checks/build-builtins.sh <profile>: build LLVM compiler-rt's builtins for a
# bare hardware profile (spec decision 11) and print the archive's path.
# Homebrew's LLVM ships compiler-rt for Darwin only, and a 32-bit board needs
# its 64-bit division and float conversion routines (__aeabi_uldivmod, ...).
# The sources are a sparse checkout of llvm-project at the tag matching the
# installed clang (llvmorg-<version>), fetched once into the cache; the build
# uses compiler-rt's own CMake for a Generic (bare-metal) system with the
# profile's triple and :cflags. Both are cached under
# ${LW_CACHE:-$HOME/.cache/let-go-wasmgc}, keyed by version, triple and
# cflags, so profiles for the same board share one build.
# Needs: clang, llvm-ar, llvm-ranlib, llvm-nm (LLVM_BIN), cmake, ninja, git.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
profile=${1:?usage: build-builtins.sh <profile>}
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
cache=${LW_CACHE:-$HOME/.cache/let-go-wasmgc}
field() { "$LG" -source-paths "$here/src" "$here/checks/profile-field.lg" "$profile" "$1"; }
ver=$("$llvm/clang" --version | sed -nE '1s/.*version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
triple=$(field triple)
read -r -a cflags <<<"$(field cflags)"
src=$cache/llvm-project-$ver
out=$cache/builtins-$ver-$triple-$(printf '%s ' "${cflags[@]}" | md5 -q | cut -c1-8)
lib=$out/lib/generic/libclang_rt.builtins-$(echo "$triple" | cut -d- -f1).a
if [ -f "$lib" ]; then echo "$lib"; exit 0; fi
mkdir -p "$cache"
if [ ! -d "$src/compiler-rt/lib/builtins" ]; then
  rm -rf "$src.tmp$$"
  git clone -q --depth 1 --filter=blob:none --sparse --branch "llvmorg-$ver" https://github.com/llvm/llvm-project.git "$src.tmp$$" >&2
  git -C "$src.tmp$$" sparse-checkout set compiler-rt/lib/builtins compiler-rt/cmake cmake llvm/cmake >&2
  mv "$src.tmp$$" "$src"
fi
rm -rf "$out"
cmake -S "$src/compiler-rt/lib/builtins" -B "$out" -G Ninja \
  -DCMAKE_C_COMPILER="$llvm/clang" -DCMAKE_ASM_COMPILER="$llvm/clang" \
  -DCMAKE_AR="$llvm/llvm-ar" -DCMAKE_RANLIB="$llvm/llvm-ranlib" -DCMAKE_NM="$llvm/llvm-nm" \
  -DCMAKE_SYSTEM_NAME=Generic -DCMAKE_SYSTEM_PROCESSOR="$(echo "$triple" | cut -d- -f1)" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_C_COMPILER_TARGET="$triple" -DCMAKE_ASM_COMPILER_TARGET="$triple" \
  -DCMAKE_C_FLAGS="${cflags[*]} -ffreestanding" -DCMAKE_ASM_FLAGS="${cflags[*]}" \
  -DCOMPILER_RT_BAREMETAL_BUILD=ON -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DCOMPILER_RT_BUILD_BUILTINS=ON \
  -DLLVM_CMAKE_DIR="$src/llvm/cmake/modules" > "$out.cmake.log" 2>&1 || { tail -20 "$out.cmake.log" >&2; exit 1; }
ninja -C "$out" > "$out.ninja.log" 2>&1 || { tail -20 "$out.ninja.log" >&2; exit 1; }
[ -f "$lib" ] || { echo "build-builtins: no $lib after the build" >&2; exit 1; }
echo "$lib"
