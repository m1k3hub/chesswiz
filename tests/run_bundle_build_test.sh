#!/bin/sh
# Bundle build (review findings B10, B12): a configured path with sed
# metacharacters reaches the bundle literally, and an unreadable source
# fails the build without replacing the bundle. Builds a copy of tcl/ in
# a scratch directory; the working tree is not touched.
set -u
root=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'chmod -R u+rw "$work"; rm -rf "$work"' EXIT INT TERM HUP
(cd "$root" && git ls-files -z tcl | xargs -0 tar -cf - | tar -xf - -C "$work") || exit 1
cp "$root/Makefile.in" "$root/Makefile.conf" "$root/Makefile.version" "$work/"
fail=0

path='/opt/a&b#c\d'"'"'e'
make -s -C "$work/tcl" chesswiz DATADIR="$path" >"$work/log" 2>&1
if [ $? -ne 0 ] || ! grep -aqF "$path" "$work/tcl/chesswiz"; then
	echo "FAIL bundle-literal-path"; cat "$work/log"; fail=1
else
	echo "ok   bundle-literal-path"
fi

cp "$work/tcl/chesswiz" "$work/prev"
src=$(ls "$work"/tcl/*.tcl | head -1)
chmod 000 "$src"
touch "$work/tcl/Makefile"
if make -s -C "$work/tcl" chesswiz >"$work/log" 2>&1; then
	echo "FAIL bundle-unreadable-source: the build succeeded"; fail=1
elif ! cmp -s "$work/prev" "$work/tcl/chesswiz"; then
	echo "FAIL bundle-unreadable-source: the bundle was replaced"; fail=1
else
	echo "ok   bundle-unreadable-source"
fi
chmod 644 "$src"
exit $fail
