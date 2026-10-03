#!/usr/bin/env bash
# install.sh — install tgc-dev-tools into a Claude Code project
#
# Usage:
#   ./install.sh <destination>                        # destination is required, there is no default
#   ./install.sh /home/rootvault/Dokumente/hl_claw_bot/.claude
#   ./install.sh /home/rootvault/Dokumente/hl_game_backend/.claude
#   ./install.sh /path/to/project/.claude             # any other project
#   ./install.sh --help
#
# <destination> is the .claude directory itself (it receives agents/, commands/, skills/).
# Same-named files in the destination are overwritten. Both target repos list .claude/ in
# their .gitignore, so the installed copies are untracked there; this repo is the versioned source.
# ~/.claude as destination overwrites the global skills of the same name, which have drifted
# from this repo (issue #3) - compare first.
# Exit: 0 installed · 2 no destination given

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./install.sh <destination>

  <destination>  the .claude directory to install into, for example
                   /home/rootvault/Dokumente/hl_claw_bot/.claude
                   /home/rootvault/Dokumente/hl_game_backend/.claude

Copies agents/*.md, commands/*.md and every skills/<name>/ of this repo into
<destination>, overwriting files of the same name. There is no default destination.
USAGE
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    usage >&2
    echo "install.sh: destination required (nothing installed)" >&2
    exit 2
    ;;
esac

# Superseded by issue #4 (a bare ./install.sh wrote into hl_claw_bot without being asked):
# DEST="${1:-/home/rootvault/Dokumente/hl_claw_bot/.claude}"
DEST="$1"
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
