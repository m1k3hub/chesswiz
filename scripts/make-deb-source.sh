#!/bin/bash
# Builds a Debian source package of Scidb from HEAD into OUTDIR:
#   scripts/make-deb-source.sh OUTDIR
# On the target machine:
#   sudo apt build-dep ./chesswiz_*.dsc   (or install the Build-Depends)
#   dpkg-source -x chesswiz_*.dsc && cd chesswiz-*/ && dpkg-buildpackage -b -uc -us
#   sudo apt install ../chesswiz_*.deb
# The package is self-contained: engine networks and Rust crates are
# included, so the build needs no network.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mkdir -p "$1" && cd "$1" && pwd)
sha=$(git -C "$root" rev-parse --short HEAD)
date=$(git -C "$root" log -1 --format=%cd --date=short)
version="1.0.r1493+git$(echo $date | tr -d -).$sha"
tree=$out/chesswiz-$version
rm -rf "$tree"; mkdir -p "$tree"

git -C "$root" archive HEAD | tar -x -C "$tree"
cp -r "$root/debian" "$tree/"
cp "$root"/engines/stockfish/src/nn-*.nnue "$tree/engines/stockfish/src/"
rsync -a --exclude target --exclude reckless-scidb --exclude reckless-chesswiz "$root/engines/reckless/" "$tree/engines/reckless/"
(cd "$tree/engines/reckless" && cargo vendor --quiet vendor > /dev/null &&
	# dpkg-source leaves out files such as .gitignore; cargo must not miss them
	for c in vendor/*/.cargo-checksum.json; do sed -i 's/"files":{[^}]*}/"files":{}/' "$c"; done &&
	printf '\n[source.crates-io]\nreplace-with = "vendored-sources"\n\n[source.vendored-sources]\ndirectory = "vendor"\n' >> .cargo/config.toml)

echo "$sha" > "$tree/debian/git-sha"
echo "$date" > "$tree/debian/git-date"
cat > "$tree/debian/changelog" <<EOF
chesswiz ($version) unstable; urgency=medium

  * Build of commit $sha ($date).

 -- Michael Thomas <thomas.g.mike@gmail.com>  $(date -R)
EOF
(cd "$out" && dpkg-source -b "$(basename "$tree")")
ls -la "$out"/chesswiz_"$version"*
