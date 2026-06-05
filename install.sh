#!/usr/bin/env bash
# install.sh — install tgc-dev-tools into a Claude Code project
#
# Usage:
#   ./install.sh                                      # install into hl_claw_bot (default)
#   ./install.sh /path/to/project/.claude             # install into specific project
#   ./install.sh ~/.claude                            # install globally

set -euo pipefail

DEST="${1:-/home/rootvault/Dokumente/hl_claw_bot/.claude}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing tgc-dev-tools into: $DEST"

# Create target directories
mkdir -p "$DEST/agents" "$DEST/commands" "$DEST/skills"

# Install agents
for f in "$SCRIPT_DIR/agents/"*.md; do
  name=$(basename "$f")
  cp "$f" "$DEST/agents/$name"
  echo "  [agent] $name"
done

# Install commands
for f in "$SCRIPT_DIR/commands/"*.md; do
  name=$(basename "$f")
  cp "$f" "$DEST/commands/$name"
  echo "  [command] $name"
done

# Install skills (each skill is a directory; copy SKILL.md + any references/,
# assets/, and bundled files like PRESETS.md — but not eval scaffolding).
for skill_dir in "$SCRIPT_DIR/skills/"*/; do
  name=$(basename "$skill_dir")
  mkdir -p "$DEST/skills/$name"
  cp -r "$skill_dir." "$DEST/skills/$name/"
  rm -rf "$DEST/skills/$name/evals"   # evals are for testing the skill, not runtime
  echo "  [skill] $name"
done

echo ""
echo "Done. Installed $(ls "$SCRIPT_DIR/agents" | wc -l) agents, $(ls "$SCRIPT_DIR/commands" | wc -l) commands, $(ls -d "$SCRIPT_DIR/skills"/*/ | wc -l) skills."
echo "Restart Claude Code to pick up new skills."
