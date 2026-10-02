#!/usr/bin/env bash
# checks/attest.sh — P5.4: attestation reuse for the gate.
#
#   attest.sh key <id>        print the input key of a row: a hash over every
#                             input the affected.sh table names for it (files
#                             listed by `git ls-files -co --exclude-standard`,
#                             so ignored caches such as src/.rtlib never count),
#                             the external corpora's HEAD + working-tree diff,
#                             the row's items.tsv line, the lg binary and the
#                             node version. Exit 2 when the table has no row.
#   attest.sh record <id>     store the current key as the row's last green run
#   attest.sh fresh <id>      exit 0 iff the stored key equals the current key
#   attest.sh clear [<id>]    forget one row or all of them
#   attest.sh                 self-test (the P5.4 row): the key moves when a
#                             new file appears under an input dir and moves
#                             back when it is removed; a file outside the row's
#                             inputs leaves it alone; then, if every phase-2 row
#                             is attested fresh, `gate.sh 2` must finish in
#                             under 60 s with every row ok (the "second gate on
#                             an unchanged tree" claim), else it says which rows
#                             are stale and exits 1 (run gate.sh 2 once first).
#
# Store: checks/.attest/<id> (gitignored: it is this machine's memory of what
# ran green here, not a fact about the tree). gate.sh consults `fresh` before
# running a row and prints `ok   <id> (attested)`; run.sh and gate.sh call
# `record` after a row exits 0. LW_ATTEST=0 turns both off for one run.
# What the key cannot see is what the affected.sh table does not name (the
# table is the one place to extend when a check grows an input, as its
# header says); the gate is therefore only as honest as that table, which is
# why `gate.sh <n>` for a phase gate decision is run with LW_ATTEST=0.
set -uo pipefail
cd "$(dirname "$0")/.."
store=checks/.attest
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}

inputs_of() { checks/affected.sh --all | awk -F'\t' -v id="$1" '$1==id{print $2; exit}'; }

key() {
  local id=$1 inputs tok
  inputs=$(inputs_of "$id"); [ -n "$inputs" ] || { echo "attest: no affected.sh row for $id" >&2; return 2; }
  {
    awk -F'\t' -v id="$id" '$1==id{print; exit}' checks/items.tsv
    echo "lg $(shasum "$LG" | cut -c1-40)"
    echo "node $(node --version 2>/dev/null)"
    for tok in $inputs; do
      case $tok in
        xsofy|legmacs)
          echo "$tok $(git -C "$HOME/projects-new/3p/$tok" rev-parse HEAD 2>/dev/null) $(git -C "$HOME/projects-new/3p/$tok" diff HEAD 2>/dev/null | shasum | cut -c1-40)" ;;
        *)
          # a dir prefix or one file; ls-files is relative to this dir, sorted
          git ls-files -co --exclude-standard -z -- "$tok" 2>/dev/null | sort -z | xargs -0 shasum 2>/dev/null ;;
      esac
    done
  } | shasum | cut -c1-40
}

case ${1:-selftest} in
  key)    key "${2:?id}" ;;
  record) k=$(key "${2:?id}") || exit 2; mkdir -p "$store"; printf '%s\n' "$k" >"$store/$2" ;;
  fresh)  k=$(key "${2:?id}") || exit 2; [ -f "$store/$2" ] && [ "$(cat "$store/$2")" = "$k" ] ;;
  clear)  if [ -n "${2:-}" ]; then rm -f "$store/$2"; else rm -rf "$store"; fi ;;
  selftest)
    fail=0
    k0=$(key P1.0); probe=corpus/scalar/.attest-probe-$$.lg
    [ -e "$probe" ] && { echo "attest: probe file exists?!"; exit 1; }
    echo ";; attest probe" >"$probe"; k1=$(key P1.0); rm -f "$probe"; k2=$(key P1.0)
    [ "$k0" != "$k1" ] && echo "ok   key moves on a new file under an input dir" || { echo "FAIL key did not move for $probe"; fail=1; }
    [ "$k0" = "$k2" ] && echo "ok   key returns when the file is removed" || { echo "FAIL key did not return"; fail=1; }
    probe2=.attest-probe-$$.md; echo x >"$probe2"; k3=$(key P1.0); rm -f "$probe2"
    [ "$k0" = "$k3" ] && echo "ok   key ignores a file outside the row's inputs" || { echo "FAIL key moved for $probe2"; fail=1; }
    [ $fail = 0 ] || exit 1
    stale=()
    while IFS= read -r id; do checks/attest.sh fresh "$id" || stale+=("$id"); done \
      < <(awk -F'\t' '$1 !~ /^#/ && $2==2 && $1 !~ /GATE/{print $1}' checks/items.tsv)
    if [ ${#stale[@]} -gt 0 ]; then echo "phase-2 rows not attested fresh: ${stale[*]}"; echo "run checks/gate.sh 2 once on this tree, then rerun"; exit 1; fi
    t0=$(date +%s); out=$(checks/gate.sh 2 2>/dev/null); rc=$?; dt=$(( $(date +%s) - t0 ))
    echo "$out"; echo "second gate.sh 2: ${dt}s exit $rc"
    [ $rc = 0 ] && [ $dt -lt 60 ] && ! printf '%s' "$out" | grep -q FAIL ;;
  *) echo "usage: attest.sh [key|record|fresh|clear] [id]" >&2; exit 2 ;;
esac
