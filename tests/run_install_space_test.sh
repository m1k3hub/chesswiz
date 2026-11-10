#!/bin/sh
# Installation into a prefix with a space (review finding B11): `make
# install` puts down the same files as with a plain prefix, and `make
# uninstall` takes them away again (player photos stay, by design).
# Runs in bubblewrap on a throwaway overlay of the tree: nothing outside
# the sandbox is written. Needs a built tree, bwrap and xvfb-run.
set -u
command -v bwrap >/dev/null 2>&1 || { echo "skip: bwrap not installed"; exit 0; }
root=$(cd "$(dirname "$0")/.." && pwd -P)

bwrap --ro-bind / / --tmpfs /tmp --dev-bind /dev /dev --proc /proc --unshare-net \
	--unshare-pid --die-with-parent --overlay-src "$root" --tmp-overlay "$root" \
	--chdir "$root" sh -c '
	mkdir -p /tmp/home/.local/share/icons/hicolor /tmp/home/.local/share/applications /tmp/.X11-unix
	chmod 1777 /tmp/.X11-unix
	export HOME=/tmp/home
	fail=0
	n=0
	for P in "/tmp/prefix" "/tmp/pre fix"; do
		n=$((n + 1))
		set -- BINDIR="$P/bin" SHAREDIR="$P/share/chesswiz" DATADIR="$P/share/chesswiz" \
			ENGINESDIR="$P/games" MANDIR="$P/man" LIBDIR="$P/lib" FONTDIR="$P/fonts"
		if ! xvfb-run -a make install "$@" >/tmp/log 2>&1; then
			echo "FAIL install [$P]"; tail -5 /tmp/log; fail=1; continue
		fi
		find "$P" -type f | sed "s|^$P||" | sort >"/tmp/files-$n"
		if ! make uninstall "$@" >/tmp/log 2>&1; then
			echo "FAIL uninstall [$P]"; tail -5 /tmp/log; fail=1; continue
		fi
		left=$(find "$P" -type f -not -path "*/photos/*" | wc -l)
		[ "$left" -eq 0 ] || { echo "FAIL uninstall [$P] left $left files"; fail=1; }
	done
	if [ -s /tmp/files-1 ] && cmp -s /tmp/files-1 /tmp/files-2; then
		echo "ok   install-space ($(wc -l </tmp/files-1) files)"
	else
		echo "FAIL install-space: the spaced prefix got different files"; fail=1
	fi
	[ -d "/tmp/pre" ] && { echo "FAIL install-space: wrote into /tmp/pre"; fail=1; }
	exit $fail
'
