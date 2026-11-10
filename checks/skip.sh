# Sourced by the corpus runners: the one reader of a corpus directory's SKIP file.
# A line names a program by basename. Bare, it is skipped in every row; as
# "<row> name", only in that row. A whole-line `#` comment is the reason for the
# names under it; text after `#` on a name line is ignored.
# skip_reason <program> <row>: prints the reason and returns 0 when the program is listed.
skip_reason() {
  local sf; sf=$(dirname "$1")/SKIP
  [ -f "$sf" ] || return 1
  awk -v b="$(basename "$1")" -v r="$2" '
    /^[ \t]*#/ {c=$0; sub(/^[ \t]*# */, "", c); next}
    {sub(/#.*/, "")}
    (NF==1 && $1==b) || (NF==2 && r!="" && $1==r && $2==b) {print c; found=1; exit}
    END {exit !found}' "$sf"
}
