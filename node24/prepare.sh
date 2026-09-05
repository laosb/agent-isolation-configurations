#!/usr/bin/env bash
# Node.js 24 (current LTS) in $HOME, for configurations that need a Node
# runtime — the default image (buildpack-deps:scm) ships none.
#
# The `node` configuration is a symlink to the newest of these directories, so a
# dependent can `dependsOn` "node" to track LTS or "node24" to pin the major.
# Both names share this tree, so activating both is harmless.
#
# Defines no entrypoint: this is a dependency, not an agent.
#
# Dependents that install a global npm package should target the persistent
# $HOME rather than the image: `npm install -g --prefix "$HOME/.local"` puts the
# binary in $HOME/.local/bin (already on PATH) and never needs sudo, whether
# node came from here or from the image.

set -euo pipefail

MAJOR=24
# Used when the latest release cannot be resolved (no network to nodejs.org,
# rate limited, ...).
FALLBACK_VERSION="24.20.0"
PREFIX="$HOME/.local/node$MAJOR"

# An image-provided Node is good enough when it is new enough and brings npm
# along. PATH already carries this configuration's bin directory, so a previous
# session's install takes this path too and re-running stays near-instant.
usable_node() {
  command -v node &>/dev/null || return 1
  command -v npm &>/dev/null || return 1
  local major
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null)" || return 1
  case "$major" in '' | *[!0-9]*) return 1 ;; esac
  [ "$major" -ge "$MAJOR" ]
}

usable_node && exit 0

case "$(uname -m)" in
  x86_64 | amd64) arch="x64" ;;
  aarch64 | arm64) arch="arm64" ;;
  armv7* | armhf) arch="armv7l" ;;
  ppc64le | powerpc64le) arch="ppc64le" ;;
  s390x) arch="s390x" ;;
  *)
    echo "node: no official Node build for $(uname -m)" >&2
    exit 1
    ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# SHASUMS256.txt doubles as the version oracle and the integrity check, so one
# fetch covers both.
sums="$tmp/SHASUMS256.txt"
version="${NODE_VERSION:-}"
if [ -z "$version" ] &&
  curl -fsSL "https://nodejs.org/dist/latest-v$MAJOR.x/SHASUMS256.txt" -o "$sums" 2>/dev/null; then
  version="$(sed -n "s/.*  node-v\([0-9.]*\)-linux-$arch\.tar\.gz\$/\1/p" "$sums" | head -n1)"
fi
version="${version:-$FALLBACK_VERSION}"

tarball="node-v$version-linux-$arch.tar.gz"

echo "==> Installing Node $version..."

curl -fsSL "https://nodejs.org/dist/v$version/$tarball" -o "$tmp/$tarball"

# Only verifiable when the checksums describe the version we actually resolved;
# after a fallback or an explicit $NODE_VERSION they may not.
if command -v sha256sum &>/dev/null && [ -s "$sums" ] && grep -q " $tarball\$" "$sums"; then
  (cd "$tmp" && grep " $tarball\$" SHASUMS256.txt | sha256sum -c --quiet -)
fi

# Unpack beside the target and swap it in, so an interrupted run cannot leave a
# half-extracted $PREFIX that the next session's fast path would accept.
tar -xzf "$tmp/$tarball" -C "$tmp"
mkdir -p "$(dirname "$PREFIX")"
rm -rf "$PREFIX.incoming"
mv "$tmp/node-v$version-linux-$arch" "$PREFIX.incoming"
rm -rf "$PREFIX"
mv "$PREFIX.incoming" "$PREFIX"

# Check what we just unpacked by path; whether PATH agrees is a separate
# question, asked right after.
"$PREFIX/bin/node" -v >/dev/null
"$PREFIX/bin/npm" --version >/dev/null

# PATH already contains additionalBinPaths, so this also proves the entrypoint
# and later configurations resolve the new runtime rather than an older node the
# image happens to ship earlier in PATH.
if ! usable_node; then
  echo "node: installed $PREFIX, but PATH resolves node to $(command -v node || echo 'nothing')" >&2
  exit 1
fi
