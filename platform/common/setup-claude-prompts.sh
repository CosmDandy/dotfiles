#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

PROMPTS_REPO="git@github.com:CosmDandy/claude-code-prompts.git"
PROMPTS_DIR="$HOME/.claude/prompts"

print_section "Setting up Claude Code prompts & knowledge"

if [[ -d "$PROMPTS_DIR" ]]; then
  echo "Already cloned: $PROMPTS_DIR"
  cd "$PROMPTS_DIR" && git pull --ff-only 2>/dev/null || echo "Pull skipped (offline or conflicts)"
else
  echo "Cloning $PROMPTS_REPO → $PROMPTS_DIR"
  git clone "$PROMPTS_REPO" "$PROMPTS_DIR"
fi

echo "Done. Prompts & knowledge available at $PROMPTS_DIR"
