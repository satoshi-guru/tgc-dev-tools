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
# Nothing in the destination is removed: a skill's evals/ folder is not installed, and an evals/
# folder the destination already has is left untouched (issue #8).
# ~/.claude as destination overwrites the four global skills of the same name (README, section
# "Skills that also exist in ~/.claude/skills") - run scripts/skill-drift.sh and compare first.
# The source is always the repo this file belongs to, also when it is started through a symlink (issue #35).
# Exit: 0 installed · 1 a copy failed or its own path cannot be resolved · 2 no destination given

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./install.sh <destination>

  <destination>  the .claude directory to install into, for example
                   /home/rootvault/Dokumente/hl_claw_bot/.claude
                   /home/rootvault/Dokumente/hl_game_backend/.claude

Copies agents/*.md, commands/*.md and every skills/<name>/ of this repo into
<destination>, overwriting files of the same name. There is no default destination.
A skill's evals/ folder is not installed; nothing in <destination> is removed.
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

# real_path FILE — absolute path of FILE with every symlink resolved (issue #35; the function scripts/gate.sh
# carries since issue #29): a link to the file by readlink (a chain of at most 40 links, relative targets read from
# the link's own directory), a link in the directory part by cd -P. Only bash and readlink.
real_path() {
  local p="$1" d t n=0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    d="$(cd -P "$(dirname "$p")" && pwd)" || return 1
    t="$(readlink "$p")" || return 1
    case "$t" in /*) p="$t" ;; *) p="$d/$t" ;; esac
    n=$((n + 1))
  done
  d="$(cd -P "$(dirname "$p")" && pwd)" || return 1
  printf '%s/%s\n' "$d" "$(basename "$p")"
}

# Superseded by issue #35 (started through a symlink - say ~/bin/tgc-install - this was the directory of the link:
# the install stopped with a cp error, or installed the agents/, commands/, skills/ of that directory if it had any):
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(real_path "${BASH_SOURCE[0]}")" || { echo "install.sh: cannot resolve its own path: ${BASH_SOURCE[0]} (nothing installed)" >&2; exit 1; }
SCRIPT_DIR="$(dirname "$SELF")"

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
  # Superseded by issue #8 (copy everything, then delete: the rm also removed an evals/ folder that the
  # destination already had before the install):
  # cp -r "$skill_dir." "$DEST/skills/$name/"
  # rm -rf "$DEST/skills/$name/evals"   # evals are for testing the skill, not runtime
  # Copy the skill's entries one by one and skip evals/ (it is for testing the skill, not runtime), so
  # nothing in the destination is ever removed. The second and third pattern take the hidden entries.
  for entry in "$skill_dir"* "$skill_dir".[!.]* "$skill_dir"..?*; do
    if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
      continue   # a pattern that matched nothing stays as typed
    fi
    if [ "$(basename "$entry")" = "evals" ]; then
      continue
    fi
    cp -r "$entry" "$DEST/skills/$name/"
  done
  echo "  [skill] $name"
done

echo ""
echo "Done. Installed $(ls "$SCRIPT_DIR/agents" | wc -l) agents, $(ls "$SCRIPT_DIR/commands" | wc -l) commands, $(ls -d "$SCRIPT_DIR/skills"/*/ | wc -l) skills."
echo "Restart Claude Code to pick up new skills."
