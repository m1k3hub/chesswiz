#!/usr/bin/env bash
# scripts/upstream-diff.sh [REV]
#
# Summarises how REV (default HEAD) differs from unmodified Scidb, the
# scidb-upstream branch (Scidb trunk r1531). For the full diff of one file:
#   git diff scidb-upstream HEAD -- <path>
set -euo pipefail
REV="${1:-HEAD}"
git rev-parse -q --verify scidb-upstream >/dev/null || {
	echo "upstream-diff: no scidb-upstream branch; fetch it from origin" >&2; exit 1; }
status=$(git diff --no-renames --name-status scidb-upstream "$REV")
total=$(git ls-tree -r --name-only scidb-upstream | wc -l)
count() { grep -c "^$1" <<<"$status" || true; }
mod=$(count M); del=$(count D); add=$(count A)
echo "Scidb r1531 files: $total; unchanged $((total - mod - del)), modified $mod, removed $del"
echo "Files Chesswiz added: $add"
for kind in M D A; do
	case $kind in M) echo; echo "Modified, by directory:";;
	              D) echo; echo "Removed, by directory:";;
	              A) echo; echo "Added, by directory:";; esac
	grep "^$kind" <<<"$status" | cut -f2 | awk -F/ '{print (NF>2 ? $1"/"$2 : $1)}' |
		sort | uniq -c | sort -rn | head -15
done
