# The official installer places the `agy` binary in $HOME/.local/bin.

if ! command -v agy &>/dev/null; then
  echo "==> Installing Antigravity CLI..."
  curl -fsSL https://antigravity.google/cli/install.sh | bash
fi
