#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: parallel-convert-to-sci.sh [--jobs N] [--force] <source-db> <destination.sci>

Runs multiple serial cdb2sci processes over disjoint game ranges, then merges the
temporary .sci shards into a single destination database.

Environment:
  CDB2SCI_BIN   Path to cdb2sci (default: ./src/cdb2sci relative to repo root)
  TMPDIR        Temporary directory root
EOF
}

jobs=""
force=0

while (($# > 0)); do
  case "$1" in
    --jobs)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --jobs" >&2; exit 1; }
      jobs="$1"
      ;;
    --force)
      force=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
  shift
done

[[ $# -eq 2 ]] || { usage >&2; exit 1; }

src_db="$1"
dst_db="$2"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cdb2sci_bin="${CDB2SCI_BIN:-$repo_root/src/cdb2sci}"

[[ -x "$cdb2sci_bin" ]] || {
  echo "Cannot execute cdb2sci at '$cdb2sci_bin'" >&2
  exit 1
}

if [[ -z "$jobs" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    jobs="$(nproc)"
  else
    jobs=4
  fi
fi

[[ "$jobs" =~ ^[0-9]+$ ]] || {
  echo "--jobs must be a positive integer" >&2
  exit 1
}
(( jobs >= 1 )) || {
  echo "--jobs must be at least 1" >&2
  exit 1
}

total_games="$("$cdb2sci_bin" --count-games "$src_db")"
[[ "$total_games" =~ ^[0-9]+$ ]] || {
  echo "Failed to read game count for '$src_db'" >&2
  exit 1
}

if (( total_games == 0 )); then
  echo "Source database contains no games" >&2
  exit 1
fi

if (( jobs > total_games )); then
  jobs="$total_games"
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/scidb-parallel-convert.XXXXXX")"
keep_tmp=0

cleanup() {
  if (( keep_tmp == 0 )) && [[ -d "$tmp_root" ]]; then
    rm -rf "$tmp_root"
  fi
}
trap cleanup EXIT

echo "Source games: $total_games"
echo "Workers: $jobs"
echo "Temp dir: $tmp_root"

shards=()
pids=()

for ((worker = 0; worker < jobs; ++worker)); do
  start=$(( worker * total_games / jobs + 1 ))
  end=$(( (worker + 1) * total_games / jobs ))

  if (( start > end )); then
    continue
  fi

  shard="$tmp_root/shard_$worker.sci"
  shards+=("$shard")

  log_file="$tmp_root/shard_$worker.log"
  echo "Shard $((worker + 1))/$jobs: games $start-$end"

  shard_cmd=( "$cdb2sci_bin" --force --start-game "$start" --end-game "$end" "$src_db" "$shard" )
  "${shard_cmd[@]}" >"$log_file" 2>&1 &
  pids+=("$!")
done

failed=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=1
  fi
done

if (( failed != 0 )); then
  keep_tmp=1
  echo "One or more shard conversions failed. Logs kept in: $tmp_root" >&2
  exit 1
fi

merge_cmd=( "$cdb2sci_bin" )
if (( force != 0 )); then
  merge_cmd+=( --force )
fi
merge_cmd+=( "${shards[@]}" "$dst_db" )

echo "Merging ${#shards[@]} shard(s) into '$dst_db'"
"${merge_cmd[@]}"

echo "Finished: $dst_db"
