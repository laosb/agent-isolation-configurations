#!/usr/bin/env bash
# `@agentclientprotocol/claude-agent-acp` — an ACP agent backed by the Claude
# Agent SDK, so ACP clients (Zed, JetBrains, ...) can drive Claude inside the
# container.
#
# The entrypoint speaks ACP — JSON-RPC over stdio — so it is meant to be spawned
# by a client rather than typed at: run bare, it just waits on stdin.
#
# The Claude CLI the adapter drives ships as a native binary inside
# @anthropic-ai/claude-agent-sdk, so `claude` is deliberately not a dependency.
# Log in once with `agentc -c claude-acp -- --cli auth login`, which forwards to
# that bundled CLI; the credentials land in the persistent $HOME and every later
# session picks them up.
#
# Set CLAUDE_ACP_VERSION to pin or move off the latest release.

set -euo pipefail

PACKAGE="@agentclientprotocol/claude-agent-acp"

# PATH already carries additionalBinPaths, so a previous session's install is
# visible here and re-running is a no-op.
if command -v claude-agent-acp &>/dev/null && [ -z "${CLAUDE_ACP_VERSION:-}" ]; then
  exit 0
fi

echo "==> Installing $PACKAGE..."

# --prefix keeps the install inside the persistent $HOME (and off sudo) even
# when node came from the image rather than from the `node` configuration.
npm install -g --no-fund --no-audit --prefix "$HOME/.local" \
  "$PACKAGE${CLAUDE_ACP_VERSION:+@$CLAUDE_ACP_VERSION}"

# Proves the `#!/usr/bin/env node` shebang resolves against the PATH the
# entrypoint will see.
claude-agent-acp --version >/dev/null
