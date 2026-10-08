#!/usr/bin/env bash
# P12.2 (D200, spec decision 2): hardware profiles for --target llvm.
# Asserts: the default (host) profile and an explicit --profile both compile
# a scalar program; each malformed profile in corpus/llvm-profile/ fails
# with a first error line naming the profile and the field; a :tail-calls
# :uniform profile is refused as not implemented before M6; --profile beats
# LW_PROFILE; checks/profile-field.lg reads one field.
# Inputs: src/driver.lg src/lower_wasm.lg src/lower_llvm*.lg targets/
# corpus/llvm-profile/ checks/profile-field.lg.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
drv() { "$LG" -source-paths "$here/src" "$here/src/driver.lg" --target llvm "$@"; }
first_err() { sed -E 's/\x1b\[[0-9;]*m//g' "$1" | grep -m1 -E 'error' ; }
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
cp "$here/corpus/scalar/fib.clj" "$t/fib.clj"; prog=$t/fib.clj
if drv "$prog" "$t/a.ll" >"$t/a.log" 2>&1; then ok "default profile"; else bad "default profile: $(first_err "$t/a.log")"; fi
hp=$("$LG" -source-paths "$here/src" "$here/checks/profile-field.lg" host name 2>/dev/null)
if [ -n "$hp" ] && drv --profile "$hp" "$prog" "$t/b.ll" >"$t/b.log" 2>&1; then ok "--profile $hp"; else bad "--profile host ($hp): $(first_err "$t/b.log" 2>/dev/null)"; fi
for f in bad-word:word-bits bad-fixnum:fixnum-bits bad-tailcalls:tail-calls missing-triple:triple uniform:tail-calls; do
  n=${f%%:*} field=${f#*:}
  if drv --profile "$here/corpus/llvm-profile/$n.edn" "$prog" "$t/$n.ll" >"$t/$n.log" 2>&1; then
    bad "$n: compiled"
  else
    e=$(first_err "$t/$n.log")
    case "$e" in *"lower-wasm: profile $n: :$field"*) ok "$n: $e";; *) bad "$n: $e";; esac
  fi
done
case "$(first_err "$t/uniform.log")" in *"not implemented before M6"*) ok "uniform refused as M6";; *) bad "uniform refusal text";; esac
if LW_PROFILE="$here/corpus/llvm-profile/bad-word.edn" drv --profile "$hp" "$prog" "$t/c.ll" >"$t/c.log" 2>&1; then ok "--profile beats LW_PROFILE"; else bad "--profile beats LW_PROFILE: $(first_err "$t/c.log")"; fi
w=$("$LG" -source-paths "$here/src" "$here/checks/profile-field.lg" host-aarch64-darwin word-bits 2>&1)
[ "$w" = 64 ] && ok "profile-field word-bits = 64" || bad "profile-field word-bits: $w"
exit $fail
