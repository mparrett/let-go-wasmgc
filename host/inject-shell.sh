#!/usr/bin/env bash
# host/inject-shell.sh <index.html> <shell.html> — put xsofy's client shell
# into a `lg -w -w-shell none` bundle's index.html, before </body>, wrapped in
# sentinel comments so a second run replaces the block instead of adding one.
# The shell binds to the runtime only through window.LetGoHost. The same
# injection xsofy's own tools/inject_shell.lg does (xsofy#78), in bash, so the
# browser rows (host/build-xsofy-serve.sh, checks/lane5.sh's stock lane) need
# nothing outside this repository.
set -euo pipefail

index=${1:?usage: inject-shell.sh <index.html> <shell.html>}
shell=${2:?usage: inject-shell.sh <index.html> <shell.html>}
start="<!--XSOFY-SHELL-START-->"
end="<!--XSOFY-SHELL-END-->"

[ -f "$index" ] || { echo "inject-shell: no $index" >&2; exit 1; }
[ -f "$shell" ] || { echo "inject-shell: no $shell" >&2; exit 1; }
# the bundle must be the shell-less variant: it exposes LetGoHost and has a </body>
grep -q "window.LetGoHost" "$index" || { echo "inject-shell: no window.LetGoHost in $index; build with 'lg -w -w-shell none'" >&2; exit 1; }
grep -q "</body>" "$index" || { echo "inject-shell: no </body> in $index" >&2; exit 1; }

if grep -qF "$start" "$index"; then
  awk -v s="$start" -v e="$end" 'index($0, s) { skip = 1 } !skip { print } index($0, e) { skip = 0 }' "$index" >"$index.tmp"
  command mv "$index.tmp" "$index"
fi
awk -v start="$start" -v end="$end" -v shellfile="$shell" '
  /<\/body>/ && !done { print start; while ((getline line < shellfile) > 0) print line; print end; done = 1 }
  { print }
' "$index" >"$index.tmp"
command mv "$index.tmp" "$index"
echo "inject-shell: injected $shell into $index"
