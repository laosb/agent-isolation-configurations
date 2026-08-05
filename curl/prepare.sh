#!/usr/bin/env bash
# Puts a static curl in $HOME for base images that ship without one, so that the
# usual `curl -fsSL <installer> | bash` bootstrap works everywhere. Any
# configuration that pipes an installer through curl should `dependsOn` this one.
#
# No-op when the image already provides curl, which is the common case.

set -euo pipefail

if command -v curl &>/dev/null; then
  exit 0
fi

BIN_DIR="$HOME/.local/bin"
REPO="stunnel/static-curl"
# Used when the latest release cannot be resolved (no API access, rate limited).
FALLBACK_VERSION="8.21.0"

case "$(uname -m)" in
  x86_64 | amd64) arch="x86_64" ;;
  aarch64 | arm64) arch="aarch64" ;;
  armv7* | armhf) arch="armv7" ;;
  armv6* | armv5*) arch="armv5" ;;
  i386 | i486 | i586 | i686) arch="i686" ;;
  riscv64) arch="riscv64" ;;
  s390x) arch="s390x" ;;
  ppc64le | powerpc64le) arch="powerpc64le" ;;
  loongarch64) arch="loongarch64" ;;
  *)
    echo "curl: unsupported architecture $(uname -m)" >&2
    exit 1
    ;;
esac

# curl is the thing we are missing, so bootstrap with whatever else is around.
if command -v wget &>/dev/null; then
  fetch() { wget -qO "$2" "$1"; }
elif command -v python3 &>/dev/null; then
  fetch() {
    python3 -c 'import shutil, sys, urllib.request
with urllib.request.urlopen(sys.argv[1]) as r:
    out = sys.stdout.buffer if sys.argv[2] == "-" else open(sys.argv[2], "wb")
    shutil.copyfileobj(r, out)' "$1" "$2"
  }
else
  echo "curl: need curl, wget or python3 to bootstrap the download" >&2
  exit 1
fi

# tar(1) shells out to xz(1) for .tar.xz and minimal images tend to omit it.
install_xz() {
  command -v sudo &>/dev/null || return 1
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends xz-utils
  elif command -v apk &>/dev/null; then
    sudo apk add --no-cache xz
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y xz
  elif command -v yum &>/dev/null; then
    sudo yum install -y xz
  else
    return 1
  fi
}

version="${STATIC_CURL_VERSION:-}"
if [ -z "$version" ]; then
  version="$(fetch "https://api.github.com/repos/$REPO/releases/latest" - 2>/dev/null |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)" || true
fi
version="${version:-$FALLBACK_VERSION}"

echo "==> Installing static curl $version..."

tarball="curl-linux-${arch}-musl-${version}.tar.xz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch "https://github.com/$REPO/releases/download/$version/$tarball" "$tmp/$tarball"

if ! tar -xJf "$tmp/$tarball" -C "$tmp" 2>/dev/null; then
  install_xz || {
    echo "curl: xz is required to unpack $tarball" >&2
    exit 1
  }
  tar -xJf "$tmp/$tarball" -C "$tmp"
fi

binary="$(find "$tmp" -type f -name curl | head -n1)"
if [ -z "$binary" ]; then
  echo "curl: $tarball did not contain a curl binary" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
install -m 0755 "$binary" "$BIN_DIR/curl"

# PATH already contains additionalBinPaths, so this also proves later
# configurations will pick the new binary up.
curl --version >/dev/null
