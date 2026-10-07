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
# The line before the last reads "Done. Installed N agents, M commands, K skills.": N, M and K count what this run
# copied, one per "[agent]" / "[command]" / "[skill]" line above it (issue #54; before, ls over the source folders).
# ~/.claude as destination overwrites the four global skills of the same name (README, section
# "Skills that also exist in ~/.claude/skills") - run scripts/skill-drift.sh and compare first.
# The source is always the repo this file belongs to, also when it is started through a symlink (issue #35).
# The source is looked at before anything is written: without agents/, commands/ and skills/ beside this file the
# install stops with one line that names the missing folders, and the destination is not created (issue #45).
# A folder that is there but holds nothing to install - agents/ or commands/ without a *.md, skills/ without a
# directory - means "nothing of that kind to install": the rest is installed and the install ends with exit 0, also
# when all three are empty. No start leaves an entry named "*" in the destination (issue #53).
# Exit: 0 installed (also when a folder, or all three, had nothing to install) · 1 a copy failed, its own path
#       cannot be resolved, or the source has no agents/, commands/ or skills/ (the last two: nothing installed) ·
#       2 no destination given

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
Without agents/, commands/ and skills/ beside install.sh nothing is installed (exit 1).
One of the three being empty is no error: nothing of that kind is installed (exit 0).
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

# issue #45: look at the source before anything is written. Until then the mkdir below ran first: from a source
# without agents/ the install stopped with a cp error on an unmatched pattern and left agents/, commands/ and skills/
# behind in a destination that did not have them; without commands/ it had installed the agents by then; without
# skills/ it ended with exit 0 and a skill directory named "*". Folders only - what is inside them is not looked at.
# Since issue #53 that last sentence has a second half: this check still reads folders only, and a folder that is
# there but holds nothing to install is no reason to stop - the loops below skip it (see the comment above them).
missing=""
for d in agents commands skills; do
  [ -d "$SCRIPT_DIR/$d" ] || missing="${missing:+$missing, }$d/"
done
if [ -n "$missing" ]; then
  echo "install.sh: not a checkout of tgc-dev-tools: no $missing in $SCRIPT_DIR (nothing installed)" >&2
  exit 1
fi

# issue #54: one counter per kind, raised where the "[agent]" / "[command]" / "[skill]" line is printed, so the
# "Done." line says what this run copied. n=$((n + 1)) and not ((n++)): under set -e the second ends the install
# when n is 0.
n_agents=0
n_commands=0
n_skills=0

echo "Installing tgc-dev-tools into: $DEST"

# Create target directories
mkdir -p "$DEST/agents" "$DEST/commands" "$DEST/skills"

# issue #53: a folder with nothing to install. In bash a pattern that matched nothing stays as typed, so each of
# the three loops below runs once with the pattern itself when its folder holds no *.md (no skill directory). Until
# issue #53 that one round was taken for a file: cp stopped the install on "agents/*.md" or "commands/*.md" (exit 1,
# with what the loops before it had installed already in the destination), and the skills loop made a directory
# named "*" in the destination and the install ended with exit 0. Each loop now skips that round, the way the loop
# over a skill's entries does since issue #8 - an empty folder means "nothing of that kind to install".

# Install agents
for f in "$SCRIPT_DIR/agents/"*.md; do
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then
    continue   # issue #53: no *.md in agents/ - the pattern stays as typed
  fi
  name=$(basename "$f")
  cp "$f" "$DEST/agents/$name"
  echo "  [agent] $name"
  n_agents=$((n_agents + 1))
done

# Install commands
for f in "$SCRIPT_DIR/commands/"*.md; do
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then
    continue   # issue #53: no *.md in commands/ - the pattern stays as typed
  fi
  name=$(basename "$f")
  cp "$f" "$DEST/commands/$name"
  echo "  [command] $name"
  n_commands=$((n_commands + 1))
done

# Install skills (each skill is a directory; copy SKILL.md + any references/,
# assets/, and bundled files like PRESETS.md — but not eval scaffolding).
for skill_dir in "$SCRIPT_DIR/skills/"*/; do
  if [ ! -d "$skill_dir" ]; then
    continue   # issue #53: no directory in skills/ - the pattern stays as typed (before: a skill directory named "*")
  fi
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
  n_skills=$((n_skills + 1))
done

echo ""
# Superseded by issue #54 (the numbers came from ls over the source folders, not from what the loops copied: an
# entry of agents/ or commands/ that is no *.md was counted and not installed - "Installed 3 agents" after 2 - and
# a skills/ without a directory put an ls error line on stderr in front of this line):
# echo "Done. Installed $(ls "$SCRIPT_DIR/agents" | wc -l) agents, $(ls "$SCRIPT_DIR/commands" | wc -l) commands, $(ls -d "$SCRIPT_DIR/skills"/*/ | wc -l) skills."
echo "Done. Installed $n_agents agents, $n_commands commands, $n_skills skills."
echo "Restart Claude Code to pick up new skills."
