#!/bin/bash
# Generate translation coverage report for menu label variables
SRCDIR="$(cd "$(dirname "$0")/../.." && pwd)"
VARS="$SRCDIR/tests/tmp-app/menu-baseline/mc-vars.txt"
OUT="$SRCDIR/tests/tmp-app/menu-baseline/translation-coverage.txt"

echo "# Translation coverage for menu label variables" > "$OUT"
echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUT"
echo "#" >> "$OUT"
TOTAL=$(wc -l < "$VARS")
echo "# Menu label variables found in source: $TOTAL" >> "$OUT"
echo "" >> "$OUT"

for langfile in "$SRCDIR"/tcl/lang/*.tcl; do
    lang=$(basename "$langfile" .tcl)
    [ "$lang" = "localization" ] && continue
    
    defined=0
    missing=0
    missing_list=""
    while IFS= read -r var; do
        # Match ::mc::VarName or mc::VarName patterns
        if grep -qP "::mc::${var}\b|set\s+${var}\s+" "$langfile" 2>/dev/null; then
            ((defined++))
        else
            ((missing++))
            missing_list="$missing_list $var"
        fi
    done < "$VARS"
    
    if [ $TOTAL -gt 0 ]; then
        pct=$((100 * defined / TOTAL))
    else
        pct=0
    fi
    echo "=== $lang ===" >> "$OUT"
    echo "Coverage: $defined/$TOTAL ($pct%)" >> "$OUT"
    if [ $missing -gt 0 ] && [ $missing -le 50 ]; then
        echo "Missing ($missing):$missing_list" >> "$OUT"
    elif [ $missing -gt 50 ]; then
        echo "Missing: $missing variables (too many to list)" >> "$OUT"
    fi
    echo "" >> "$OUT"
done

echo "Written to $OUT"
