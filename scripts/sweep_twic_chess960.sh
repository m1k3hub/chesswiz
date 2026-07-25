#!/bin/bash
# Sweep TWIC issues for Chess960 games and harvest H0/g samples from each.
set -u
S=/tmp/claude-1000/-media-michael-g-thomas-sas-mirror-src-chess-scidb-code-codex/e69cd00a-4ecc-49e1-b053-852790b72609/scratchpad
REPO=/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex
UA="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
REF="https://theweekinchess.com/twic"
cd "$S"

for N in $(seq "$1" "$2"); do
  TAG="twic$N"
  [ -f "$TAG.done" ] && continue
  # PGN first (cheap): does the issue contain Chess960 games?
  if [ ! -f "$TAG.pgn" ]; then
    curl -sL -o "$TAG-g.zip" "https://theweekinchess.com/zips/${TAG}g.zip" --max-time 120 -A "$UA" -H "Referer: $REF" || { echo "$TAG: pgn download failed"; continue; }
    unzip -p "$TAG-g.zip" > "$TAG.pgn" 2>/dev/null || { echo "$TAG: pgn unzip failed"; rm -f "$TAG-g.zip"; touch "$TAG.done"; continue; }
    rm -f "$TAG-g.zip"
    sleep 2
  fi
  N960=$(grep -c '^\[Variant "Chess960"' "$TAG.pgn" || true)
  if [ "$N960" -eq 0 ]; then echo "$TAG: no chess960"; touch "$TAG.done"; rm -f "$TAG.pgn"; continue; fi
  echo "$TAG: $N960 chess960 games"

  # CBV
  if [ ! -f "$TAG.cbv" ]; then
    curl -sL -o "$TAG-c6.zip" "https://theweekinchess.com/zips/${TAG}c6.zip" --max-time 180 -A "$UA" -H "Referer: $REF" || { echo "$TAG: cbv download failed"; continue; }
    unzip -o -d "$S" "$TAG-c6.zip" >/dev/null 2>&1 || { echo "$TAG: cbv unzip failed"; rm -f "$TAG-c6.zip"; touch "$TAG.done"; continue; }
    rm -f "$TAG-c6.zip"
    sleep 2
  fi
  [ -f "$TAG.cbv" ] || { echo "$TAG: no cbv extracted"; touch "$TAG.done"; continue; }

  # extract cbh/cbg via cdb2sci temp-dir snapshot
  mkdir -p "$S/extracted"
  ( "$REPO/src/cdb2sci" --force "$S/$TAG.cbv" "$S/$TAG-conv.sci" >/dev/null 2>&1 ) &
  PID=$!
  while kill -0 $PID 2>/dev/null; do
    for d in /tmp/scidb-cbv-*; do
      [ -d "$d" ] && cp -f "$d/$TAG.cbh" "$d/$TAG.cbg" "$S/extracted/" 2>/dev/null
    done
    sleep 0.03
  done
  wait $PID
  rm -f "$S/$TAG-conv".sc?
  [ -s "$S/extracted/$TAG.cbg" ] || { echo "$TAG: cbg snapshot failed"; continue; }

  "$REPO/src/probe_cbh_chess960" "$S/extracted/$TAG.cbh" --dump-moves > "$S/${TAG}_moves.txt" 2>/dev/null
  "$REPO/src/list_cbv_headers" "$S/$TAG.cbv" > "$S/${TAG}_headers.txt" 2>/dev/null
  python3 "$S/harvest.py" "$S" "$TAG" 2>&1 | grep -E 'harvested|trimming|new entries|conflicts|MERGED|NOT MERGED' | sed "s/^/$TAG: /"
  touch "$TAG.done"
  rm -f "$S/$TAG.cbv" "$S/extracted/$TAG.cbh" "$S/extracted/$TAG.cbg"
done
echo SWEEP-DONE
