#!/usr/bin/env bash
# mk.sh <group> <name> <expect-comment> < body : write probes/<group>/<name>.lg
# (the comment line, then helper.lgh, then the body). Authoring aid only.
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$here/probes/$1"
{ echo ";; $3"; cat "$here/helper.lgh"; cat; } >"$here/probes/$1/$2.lg"
