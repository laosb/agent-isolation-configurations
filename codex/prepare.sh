# The official installer drops a static binary in $HOME/.local/bin, so unlike
# `npm i -g @openai/codex` it does not need Node in the image.

if ! command -v codex &>/dev/null; then
  echo "==> Installing Codex CLI..."
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
fi
