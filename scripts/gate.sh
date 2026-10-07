#!/usr/bin/env bash
# gate.sh — offline gate for tgc-dev-tools (fleet board gate, routing["gates"]).
# Usage: scripts/gate.sh [--selftest | --push-main [FILE ...] | --fences [FILE ...] | --help]
#        (each form is described under "Usage:" below the list of checks. This short line stands here since issue
#        #66: the store's script-intake.py looks for the word in the first 40 lines of a script, and the list of
#        checks had pushed the long form to line 42)
#
# What it checks (no internet, no dependencies beyond bash/python3 + the store's agent-file-check):
#   0. the root is a checkout of this repo: it has install.sh and README.md (issue #29). A root without them is
#      rejected and nothing else is checked or run there - before, nearly every check was skipped on such a root and
#      the gate was green on a directory it had not looked at. The root is the repo this file belongs to: a symlink
#      to this file or to scripts/ is resolved first (before, the root was the directory above the link)
#   1. bash -n over install.sh and every scripts/*.sh
#   2. agents/*.md and skills/*/SKILL.md carry YAML frontmatter with name + description;
#      commands/*.md are non-empty
#   3. .claude/agents/*.md pass ~/.claude/scripts/dev/agent-file-check.py (skipped with a note if the store is absent).
#      The checker is started in the repo root, because it looks up the paths an agent file names in its working
#      directory (issue #21: started elsewhere, the gate was red on a good tree or green on a broken one)
#   4. install.sh into a temp dir installs every agent, command and skill dir of this repo (counts match),
#      copies every entry of a skill (hidden ones too) except its evals/, and leaves an evals/ folder that a
#      destination already had as it was (issue #8). The fresh install is also in step with the source file by
#      file, agents and commands included (scripts/install-status.sh, issue #6; skipped with a note if that
#      program is not next to this file)
#   5. install.sh has no default destination (static read of the file; the gate never runs it without one)
#   6. README.md lists every agent, command, skill and script (scripts/readme-listing-check.sh; a root without
#      README.md does not get this far since issue #29, check 0)
#   7. README.md carries no `git push` command whose target is main (issue #16; one FAIL per command line, with the
#      number of the line where the command starts; a quoted command counts too, the check cannot read a "never" in
#      front of it; a root without README.md does not get this far, check 0). Since issue #18 also: a command wrapped with a backslash, options
#      between git and push (git -C dir push ...), --all / --mirror / --branches, and a push without a ref after a
#      switch or checkout to main in the same code block. Since issue #30 also: git called by its path
#      (/usr/bin/git push ...), a ref or command in single quotes, and lines that end in a carriage return (CRLF).
#      Since issue #33 also: the command word in quotes ("git" push ..., "/usr/bin/git" push ...).
#      Since issue #41 also: the subcommand in quotes (git "push" ..., git 'switch' main, git "checkout" main).
#      Since issue #32 also: a push without a ref after a switch or checkout to main in the same indented code block
#      (lines with four blanks or a tab in front, no fence; an empty line between them does not end the block).
#      Since issue #49 also: a line of three backticks or tildes is a fence line only with at most three blanks and
#      no tab in front; indented further it is one more line of that indented block and no longer ends the state.
#      Since issue #66 also: a fenced block is closed only by a line of the character that opened it, with a run at
#      least as long and nothing but blanks behind it; a line of the other character, a shorter run or a run with
#      text behind it is content of the block and no longer ends the state.
#      Since issue #69 also: a line that starts with a run of backticks and carries a backtick behind the run is no
#      fence line - it is a sentence that starts with inline code, opens no block and no longer keeps the state alive
#      to the end of the file (or reads the blocks behind it inverted, which also hid a push inside them).
#      Since issue #24 also: a push without a ref after two more ways to get main checked out in the same code block -
#      a remote branch behind a track option (git switch --track origin/main, git checkout -t origin/main, also
#      --no-track), and a rename with git branch -m / -M main. The name behind a new-branch option decides wherever
#      it stands, and a rename away from main ends the state.
#      Since issue #75 also: the options of a switch or checkout are read the way git reads them - the word behind
#      --conflict (and behind --pathspec-from-file at checkout) is its value and not the branch
#      (git switch --conflict diff3 main), short options in one word are read letter by letter
#      (git switch -ft origin/main), and a name glued to a new-branch option counts (git switch -cmain,
#      git checkout -bmain, git switch --create=main).
#      Since issue #25 the same reader also runs over every file install.sh copies into a project: agents/*.md,
#      commands/*.md and every file of a skill (hidden ones and symlinked ones too) except its evals/. One FAIL per
#      command line there as well, named by the path of the file below the root. No exceptions file exists: the
#      readout of 2026-10-06 over the 18 installed files reported nothing (see the comment at the check)
#      Since issue #51 also: a symlink to a directory below skills/<name>/ is rejected, one FAIL per link, named by
#      its path below the root and its target. install.sh copies such a link as a link and the reader does not go
#      behind it, so a push instruction in a file behind it was installed and not read. A skill's own evals (not
#      installed) stays out; a symlink to a file stays allowed and is read
# Usage:  scripts/gate.sh            # run from anywhere, also through a symlink; last line "gate: ok" (exit 0) or "gate: FAILED" (exit 1)
#          scripts/gate.sh --selftest # last line "selftest ok" (exit 0) or "selftest FAILED fail_lines=N" (exit 1) - issue #67, N = the lines above it
#          that start with "selftest FAIL:"; it proves the checks fail on 28 broken fixtures and pass on 12 good ones (+ 29 line cases and 316 block cases
#          for check 7, + 10 starts of the gate file itself, directly and through symlinks, on a good and a broken tree - issue #29,
#          + 6 starts of install.sh, directly and through symlinks, each into a temp destination - issue #35, and 4 in a source without agents/, commands/ or
#          skills/ - issue #45, and 3 with one or all of them empty - issue #53, + 8 starts of the gate file with --push-main and 1 with --help - issue #25,
#          + 9 starts of the gate file with --fences - issue #66, 2 of them since issue #69,
#          + 4 starts of install.sh whose "Done. Installed ..." line is read, 3 of them beside entries it does not copy - issue #54,
#          + 7 runs of the step that prints the selftest's last line, each over a stand-in for the cases - issue #67)
#          of these, one broken and one good fixture belong to check 3; they are skipped with a note if the store is absent
#          scripts/gate.sh --push-main [FILE ...]  # check 7 alone, as a readout (issue #25): one "FILE:LINE: command" line
#          per reported command, then the last line "push-main: ok files=N" (exit 0) or "push-main: FOUND hits=K files=N"
#          (exit 1); exit 2 and nothing read when a FILE is no readable file. Without FILE: the files check 7 reads in
#          this repo, README.md and what install.sh installs
#          scripts/gate.sh --fences [FILE ...]  # the code fences as check 7 reads them, as a readout (issue #66): one
#          "FILE:LINE: kind: text" line per fence that opens with four or more characters (long), per line inside a
#          fenced block that starts like a fence line and does not close it (inner) and per block nothing closes
#          (unclosed), then the last line "fences: files=N blocks=B long=L inner=I unclosed=U" (exit 0, whatever the
#          counts); exit 2 and nothing read when a FILE is no readable file. Without FILE: the same files as --push-main
#          scripts/gate.sh --help     # this header
set -uo pipefail

# Superseded header lines of the earlier state of this branch (PR #9, 4 broken + 2 good fixtures), kept as a comment
# when main was merged in. The header above is the valid one; these two lines are no usage text:
#   Usage:  scripts/gate.sh            # run from anywhere; last line "gate: ok" (exit 0) or "gate: FAILED" (exit 1)
#            scripts/gate.sh --selftest # proves the checks fail on 4 broken fixtures and pass on 2 good ones

# real_path FILE — absolute path of FILE with every symlink resolved (issue #29): a link to the file by readlink (a
# chain of at most 40 links, relative targets read from the link's own directory), a link in the directory part by
# cd -P. Only bash and readlink, so it does not depend on realpath or on readlink -f being there.
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

# issue #29: SELF is the program file itself, not the link the gate was started by - the root and the path of
# readme-listing-check.sh are derived from it
SELF="$(real_path "${BASH_SOURCE[0]}")" || { echo "gate.sh: cannot resolve its own path: ${BASH_SOURCE[0]}" >&2; echo "gate: FAILED"; exit 1; }
# the store program of check 3; one place, because the selftest skips its check 3 cases exactly when check 3 is skipped
AGENT_CHECKER="$HOME/.claude/scripts/dev/agent-file-check.py"
FAILS=0

fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }

# frontmatter_ok FILE "key key" — file starts with --- and the block holds every key
frontmatter_ok() {
  local file="$1" key block
  [ -s "$file" ] || return 1
  [ "$(head -n1 "$file")" = "---" ] || return 1
  block="$(awk 'NR==1{next} /^---$/{exit} {print}' "$file")"
  for key in $2; do
    printf '%s\n' "$block" | grep -q "^${key}:" || return 1
  done
  return 0
}

# FENCE_AWK — the fence rule as awk functions (issue #66), one place for the programs that read code fences:
# fence_readout (the option --fences) and readme_push_main (check 7). It is the CommonMark rule:
#   - a fence line starts, behind at most three blanks and no tab (issue #49), with a run of three or more backticks
#     or of three or more tildes
#   - outside a fenced block every such line opens one; the character and the length of its run are kept
#   - inside a fenced block only a line of the same character, with a run at least as long as the opening one and
#     nothing but blanks or tabs behind it, closes the block. Every other line there is content: a line of the other
#     character, a shorter run, and a run with text behind it (what would be an info string on an opening line)
#   - a block that nothing closes runs to the end of the file
# fence_run(s) returns the length of the run at the start of s (0 = s is no fence line) and sets FCH to the
# character of the run, FLEN to its length and FREST to what stands behind it. fence_change(s) says whether s
# changes the state held in the globals fence / fch / flen: it opens a block (fence is 0) or closes the open one.
# The caller changes the state: opening is fence = 1; fch = FCH; flen = FLEN, closing is fence = 0.
# Superseded by issue #69, kept as a comment - these two lines closed the block above:
#   Not part of the rule here: an opening line of backticks whose info string carries a backtick is inline code in
#   CommonMark and opens nothing there; here it opens a block, as every such line did before issue #66.
# Since issue #69 that is part of the rule, in fence_run:
#   - a run of backticks with a backtick somewhere behind it is no fence line (in CommonMark the info string of a
#     backtick fence may not carry a backtick): the line is a line of a paragraph that starts with inline code, it
#     opens nothing and fence_run returns 0 for it. A run of tildes may carry backticks behind it and still opens.
#     Inside a fenced block the test changes nothing: such a line has text behind its run, so it never closed.
FENCE_AWK='
    # The blanks in front are counted by hand. The first form of this function (same branch) dropped them with
    # sub(/^ ? ? ?/, "", s); run with mawk 1.3.4, a fence line with one to three blanks in front was then no fence
    # line (measured on this repo: 57 blocks read where 62 stand, 5 indented ones in 3 files missed). Why that sub
    # did not drop the blanks was not looked into; the loop needs no pattern. Superseded, kept as a comment:
    #   sub(/^ ? ? ?/, "", s); c = substr(s, 1, 1) ... FREST = substr(s, m + 1)
    function fence_run(s,   b, c, m) {
      b = 0
      while (b < 3 && substr(s, b + 1, 1) == " ") b++
      c = substr(s, b + 1, 1)
      if (c != "`" && c != "~") return 0
      m = 1
      while (substr(s, b + m + 1, 1) == c) m++
      if (m < 3) return 0
      # issue #69: a run of backticks with a backtick behind it is inline code at the start of a line, no fence
      # line. Tested with index(), which needs no pattern (see the note on sub() above). The globals are left as
      # they were, as at every other return 0.
      if (c == "`" && index(substr(s, b + m + 1), "`") > 0) return 0
      FCH = c; FLEN = m; FREST = substr(s, b + m + 1)
      return m
    }
    function fence_change(s,   m) {
      m = fence_run(s)
      if (!fence) return (m > 0)
      return (m >= flen && FCH == fch && FREST ~ /^[ \t]*$/)
    }
'

# readme_push_main FILE — prints "LINE: text" for every line that carries a `git push` command whose pushed ref or
# refspec target is the whole word main: origin main, -u origin main, HEAD:main, feat/x:main, +main, refs/heads/main,
# :main, --delete main. Returns 0 when at least one such line exists, 1 when there is none.
# How a line is read: words after "git push" up to the end of the command (&& || | ; a comment, or the backtick that
# closes inline code); options are skipped; the first other word is the remote and is skipped too; of every further
# word the part after the last ":" is the target.
# Also reported since issue #18 (the number is the line where the command starts, the text is the joined command):
#   - a wrapped command: a line that ends in a backslash is joined with the next one before the words are split
#     (not across a code fence)
#   - options between git and push: every -word is skipped, and with -C -c --git-dir --work-tree --namespace
#     --config-env the word after it as well (git -C dir push origin main)
#   - --all, --mirror, --branches (the newer name of --all), whatever the remote: they push main without naming it
#   - a push without a ref while main is checked out: after `git switch main` / `git checkout main` (also -c / -b /
#     -C / -B with the new name main) a `git push` with no ref word (nothing, or only the remote), or with the ref
#     HEAD / @, is reported. The state lives inside one fenced code block (``` or ~~~) and ends with it; outside a
#     fence it lives for one line (since issue #32: or for one indented code block, see below). A switch or
#     checkout to another branch, a new branch or --detach clears it;
#     `git checkout -- path` leaves it. `git push --tags` without a ref pushes tags only and is left alone; the word
#     after -o / --push-option / --receive-pack / --exec is an option value, not the remote.
# Also reported since issue #30:
#   - git called by its path: a command word that ends in /git (/usr/bin/git, ./git, ~/bin/git) is read like git.
#     A word that only ends in the letters git (legit, my-git, x/.git) is not, and a path or URL that ends in /git
#     matters only when the word after it (options aside) is push, switch or checkout
#   - single quotes: they are stripped like double quotes, around the ref (git push origin 'main') and around a
#     whole command (sh -c 'git switch main && git push')
#   - CRLF line endings: carriage returns at the end of a line are dropped before the line is read, so the last
#     word is main and not main + carriage return, a backslash in front of the carriage return still joins the
#     lines, and the reported text carries none
# Also reported since issue #33:
#   - the command word in quotes: "git" push, 'git' push, "/usr/bin/git" push (also a quoted path with a blank in
#     it, and /usr/bin/"git"). Quotes at the end of the command word are dropped before it is tested; what the word
#     has to be is unchanged ("legit", "my-git", "x/.git" are no command, and a quoted path or URL that ends in /git
#     matters only when the word after it, options aside, is push, switch or checkout)
# Also reported since issue #32:
#   - an indented code block (no fence): outside a fence the "main is checked out" state lives from one line to
#     the next while the lines are indented by four blanks, or by a tab after at most three blanks. An empty line
#     (nothing, or blanks and tabs only) between two indented lines belongs to the block and keeps the state, as in
#     CommonMark. The first line with text that is not indented that far ends it. The state has to be set inside
#     the indented lines: a switch to main in a line that is not indented lives for that line only, as before, so a
#     sentence that names the switch followed by an indented push is left alone.
#     Accepted limit: the check cannot tell an indented code block from the indented continuation paragraph of a
#     list item (CommonMark counts the indent from the list item's content; this check counts it from the start of
#     the line), so the state is also kept across indented prose and across a block that is nested deeper. That can
#     only report more, and only where a switch to main and a push without a ref really stand in indented lines
#     with nothing unindented between them. Since issue #49 a line of three backticks or tildes that is indented
#     by four blanks, or by a tab, is no fence line (see the block of issue #49 below).
# Superseded by the sentence above (issue #49), kept as a comment - this was the last sentence of the block:
#   A fence line indented by four blanks is still read as a fence.
# Also reported since issue #49:
#   - the fence line has an indent limit, the CommonMark rule: a line that starts with three backticks or three
#     tildes is a fence line only with at most three blanks and no tab in front of them. Indented by four blanks,
#     or by a tab (alone or after blanks), it is a line like any other: outside a fence one more line of an indented
#     code block, which keeps the state, and inside a fence content, which does not close it. So a switch to main, such
#     a line and a push without a ref in one indented block are reported (before, the line toggled the fence and
#     cleared the state). The join of a wrapped command follows the same rule: a line that ends in a backslash is
#     joined with such a line, and still not with a real fence line.
#     No longer reported: what stood behind an indented line of three backticks that nothing closed - it opened a
#     fence that lived to the end of the file, and the state lived with it across lines that are not indented.
#     Accepted limit: a fenced block inside a list item whose fence lines are indented by four blanks or more is a
#     real fence in CommonMark; this check does not see it as one. Its lines are then lines of one indented block,
#     so a switch to main and a push without a ref inside it are reported as before - but the state is no longer
#     ended by its fence lines: it lives as long as the lines stay indented (empty lines included), also from one
#     such block into the next of the same list item. That can only report more.
#     What closes a fenced block was not part of issue #49; it is the rule of issue #66, see the block below. An
#     opening line may carry text behind its run (an info string), as before.
# Superseded by the two lines above (issue #66), kept as a comment - this was the last sentence of the block:
#   Not changed: fences of more than three characters, the rule that a closing fence has to be as long as the
#   opening one and of the same character, and an info string - any fence line toggles, as before.
# Also reported since issue #66:
#   - what closes a fenced block, the CommonMark rule (FENCE_AWK above): the block is closed only by a line of the
#     character that opened it (backticks or tildes), with a run at least as long as the opening one and nothing but
#     blanks or tabs behind it. Every other line that starts like a fence line is content of the block and leaves
#     the "main is checked out" state as it is: a line of tildes in a backtick block and the other way round, a run
#     of three inside a block opened by four (how a file shows a fenced block), and a run with text behind it
#     (inside a block there is no info string). So a switch to main, such a line and a push without a ref in one
#     fenced block are reported (before, any fence line toggled the fence and cleared the state). The join of a
#     wrapped command follows the same rule: inside a block a line that ends in a backslash is joined with such a
#     line, and still not with the line that closes the block.
#     A block that nothing closes runs to the end of the file, and the state with it. That can only report more.
#     No longer reported: what stood behind a block whose inner fence-like line had ended it for the reader - the
#     real closing line then opened a block that lasted to the next fence line, and the state lived across lines
#     that stand outside every block.
#     Measured before the change with scripts/gate.sh --fences (2026-10-07): the files check 7 reads in this repo,
#     README.md and the 18 installed ones, carry 62 fenced blocks, none opened by four or more characters, no such
#     inner line and no unclosed block - the rule changes no report there.
#     No longer a limit since issue #69 (see the block below): an opening line of backticks whose info string
#     carries a backtick is inline code in CommonMark, and this check now reads it that way too.
# Superseded by the two lines above (issue #69), kept as a comment - this was the last sentence of the block:
#   Accepted limit, unchanged: an opening line of backticks whose info string carries a backtick (three backticks,
#   a word, three backticks, text) is inline code in CommonMark and opens nothing; this check reads it as an
#   opening line, as before. A closing line is never read that way, since it has nothing but blanks behind it.
# No longer reported since issue #69:
#   - what stood behind a sentence that starts with inline code in three or more backticks. A line that starts,
#     behind at most three blanks, with a run of backticks and carries a backtick somewhere behind the run is no
#     fence line (fence_run in FENCE_AWK; in CommonMark the info string of a backtick fence may not carry a
#     backtick). It is a line of a paragraph: it opens no block, and a switch to main inside its inline code lives
#     for that line only. Before, the line opened a block that nothing closed and the state lived to the end of the
#     file, across prose, to the next push without a ref.
#     Reported since then, and missed before: a switch to main and a push without a ref in a real fenced block
#     behind such a sentence. The sentence had opened a block for the check, so the opening line of the real block
#     closed it and its closing line opened the next one - every block behind the sentence was read inverted, and
#     the two commands were two lines between blocks. The issue names only the report too many; this one was found
#     while the cases were written (selftest, form 13).
#     The join of a wrapped command follows the same rule: a line that ends in a backslash is joined with such a
#     sentence, and still not with a real opening line.
#     Unchanged: a run of tildes may carry backticks behind it and still opens a block (the info string of a tilde
#     fence may hold any character); an info string without a backtick; inside a fenced block such a line was
#     content before and is content now, since a closing line has nothing but blanks behind its run; and the command
#     inside the inline code is read as before (a push to main there is a report at that line).
#     Measured with scripts/gate.sh --fences before and after the change (2026-10-07): README.md and the 18 installed
#     files carry 63 fenced blocks, none long, no inner line, none unclosed, both times - no file check 7 reads here
#     has such a line, the rule changes no report in this repo.
#     The test reads one line, as CommonMark does: a line that starts with three backticks and carries no further
#     backtick is an opening line there as well, even when a later line would close the run as inline code.
# Superseded by the block above (issue #32), kept as a comment - this stood at the head of "Still not seen":
#   an indented code block (four blanks or a tab, no fence) - a switch to main in one of its lines and a push
#   without a ref in the next are two lines outside a fence, so the state is gone (the fourth form of issue #30,
#   left out there on purpose because it changes how the state is scoped; now issue #32)
# Also reported since issue #41:
#   - the subcommand in quotes: git "push" origin main, git 'push' origin main, and in a code block
#     git "switch" main or git 'checkout' main followed by a push without a ref. A word that is push, switch or
#     checkout between one pair of quotes (the same quote in front and behind) is that subcommand, and the words
#     after it are its arguments. A quoted switch to another branch clears the state like a bare one (before, it
#     was not read and the push after it was reported). Closing punctuation behind the pair ends the command at the
#     word (sh -c 'git switch main && git "push"'), as it does behind the bare word; a quote behind the bare word
#     still closes a whole command, so in sh -c 'git push' origin main the last two words are no remote and no ref.
#     Not a pair, so not read: git 'push origin main' (one word for git) and git "push' origin main.
# Superseded by the block above (issue #41), kept as a comment - this stood in "Still not seen", between the
# variable forms and the bare carriage returns:
#   the subcommand in quotes and quotes or a backslash inside the command word (git "push" origin main,
#   gi"t" push, g\it push - issue #41; a backslash in front of the word, \git push, is seen)
# Also reported since issue #24 (two of the six forms of that issue; the other four stand in "Still not seen" below,
# each with its reason). What git does with every command named here was measured with
# scripts/branch-after-probe.sh, which runs it in a throwaway clone (git 2.43.0, 2026-10-07):
#   - a remote branch behind a track option: git switch --track origin/main, git checkout --track origin/main, the
#     short -t, --track=direct / --track=inherit, and --no-track. git derives the name of the new local branch from
#     the first word: refs/ and remotes/ in front are dropped, then everything up to the first slash, so
#     origin/main, upstream/main and refs/remotes/origin/main give main, and origin/topic/main gives topic/main.
#     A push without a ref (or of HEAD) behind such a command in the same code block is reported.
#     --no-track was expected to be left alone; the probe showed that it derives the name in the same way (the
#     branch then has no upstream, so git's default refuses the push without a ref and the push of HEAD goes to
#     main).
#   - the name behind a new-branch option decides, wherever the option stands (-c -C -b -B --create --force-create
#     --orphan): git switch --track origin/main -c main is main, git switch -c feature --track origin/main and
#     git switch --track origin/main -c feature are feature.
#     No longer reported for that reason: git switch main -c feat/x followed by a push without a ref. The first
#     word main alone decided before; the probe shows feat/x checked out.
#   - git branch -m / -M / --move with the new name main: git branch -M main, git branch -m main,
#     git branch --move main - the current branch is called main from then on. With the old name in front
#     (git branch -m master main) the text does not say whether master is the current branch; it is read as if it
#     were, which is the usual case and can only report more.
#     No longer reported: git switch main, then git branch -m trunk (or git branch -m main trunk), then a push
#     without a ref - the branch that is checked out is no longer called main (the probe: trunk, and the push is
#     refused). git branch was not read before, so the state of the switch lived on.
#     Unchanged: git branch without a move option (create, delete, copy with -c, list, -u) never changes what is
#     checked out and leaves the state as it is; the rename of another branch (git branch -m feat/a feat/b) too.
#     The subcommand in quotes (git "branch" -M main) is read like the bare word, as for push, switch and checkout.
#   Accepted limit, as for git switch main since issue #18: "main is checked out" is what the text says, not what
#   git would do with the push. Whether a push without a ref then reaches the remote main depends on the upstream of
#   the branch and on push.default, which are not in the words of the command (after git branch -M main on a branch
#   without an upstream git's default refuses it; git push -u origin HEAD always goes to main).
# Superseded by the block above and the list below (issue #24), kept as a comment - this was the end of "Still not
# seen", behind the bare carriage returns:
#   a branch change by other means (git switch --track origin/main, git branch -M main, git clone, git worktree, cd
#   into another clone), `git checkout <path>` without "--" (read as a branch, clears the state), state carried from
#   one code block to the next, a push configured elsewhere (push.default, remote.*.push, an alias), and prose: the
#   check reads commands, not sentences.
# Also reported since issue #75 (all three forms of that issue were built; what was not stands in "Still not seen"
# below). The options of git switch / git checkout are read the way git reads them; the list is what git switch -h
# and git checkout -h of git 2.43.0 print, and what git does with every command named here was measured with
# scripts/branch-after-probe.sh (2026-10-07):
#   - an option that takes a value as its own word: --conflict <style> at both commands, --pathspec-from-file
#     <file> at checkout. The word behind it is the value and is skipped, so in git switch --conflict diff3 main
#     the branch is main (before, diff3 was read as the branch, which cleared the state). With "=" the value is
#     part of the word and nothing is skipped (--conflict=diff3 main, reported before too). The other long options
#     with a value were read already (--create, --force-create, --orphan), and --recurse-submodules takes its value
#     only with "=": the probe shows git switch --recurse-submodules main on main, as the reader had it.
#     No longer reported: git switch --conflict main feat/x followed by a push without a ref - main is the value
#     there (git rejects the style and stays where it was).
#     --pathspec-from-file: with a file that names no path git switches the branch (the probe, with /dev/null).
#     With a file that names a path git checkout is documented to restore files and change no branch - that was
#     not run, the probe's clone has no file. The text does not say which file it is, so the word behind the file
#     is read as the branch, as the word behind git checkout always is. That can only report more.
#   - short options written as one word: every letter is an option of its own. d is --detach; t is --track and
#     takes the rest of the word as its mode (-tdirect); c C b B take the rest of the word as the name of the new
#     branch, or the next word when nothing is left; every other letter takes no value. So git switch -ft
#     origin/main and git checkout -qt origin/main are read like -t origin/main.
#     No longer reported: git switch -fd main followed by a push without a ref - the word carries the letter of
#     --detach (the probe: detached). Before, only the whole word -d was a detach option.
#   - the name glued to a new-branch option: git switch -cmain, -Cmain, git checkout -bmain, -Bmain, behind other
#     letters too (-fcmain), and the long options with "=" (--create=main, --force-create=main, --orphan=main).
#     Quotes in front of the glued name are dropped (-c"main"). Before, the word was skipped as an unknown option.
#     No longer reported: git switch main, then git switch -cfeat/x (or git checkout -bfeat/x, or
#     git switch --create=feat/x), then a push without a ref - the probe shows feat/x checked out; and
#     git switch -cfeat/x main, where main is the start point.
#   As before, the four letters c C b B and the long names are read at both commands, although git switch knows
#   only -c / -C and git checkout only -b / -B (git rejects the other pair). That can only report more.
# Still not seen: git reached
# through a variable or a command substitution ("$GIT" push, ${GIT} push, $(command -v git) push,
# "$(command -v git)" push - left out of issue #33 on purpose: what a variable holds cannot be read from the text,
# and a rule for "any variable followed by push" would be a guess); quotes or a backslash inside the command word
# (gi"t" push origin main, g\it push origin main - the second form of issue #41, decided there not to be built: a
# file that writes git this way does not do so by accident, and the check guards against a careless instruction,
# not against one that is hidden on purpose; a backslash in front of the word, \git push, is seen); a quoted
# option between git and the subcommand (git "-C" dir push origin main - the word does not start with a dash, so
# it is taken for the subcommand); a file whose only line ends are bare carriage
# returns (one line for awk, named in issue #33, not built there); and prose: the check reads commands, not
# sentences.
# Still not seen, the four forms of issue #24 that were decided not to be built (2026-10-07), one reason each:
#   - git clone + cd, git worktree add, cd into another clone: the push then runs in another directory. That is
#     not a state of this code block, and which branch is checked out there is not in the text
#   - `git checkout <path>` without "--" (git checkout README.md): a path and a branch cannot be told apart from
#     the text, so the word is read as a branch and clears the state. `git checkout -- <path>` leaves it
#   - a switch to main in one code block and the push without a ref in the next: the state ends with the block, as
#     scoped in issue #18. Carrying it further would report on prose that stands between two blocks
#   - a continuation backslash followed by blanks: only a backslash as the very last character of the line joins
#     it with the next one - that is the shell's rule too, there the backslash escapes the blank and joins nothing
#   - a push whose target comes from configuration (push.default, remote.*.push, branch.*.merge set with
#     git branch -u, an alias): it is not in the words of the command
# Still not seen, found while issue #75 was built and not built there (2026-10-07), one reason each:
#   - a long option of switch / checkout cut down to a unique prefix, which git accepts (git switch --conf diff3
#     main, git switch --tr origin/main, git switch --cre=main pass; git switch --det main is reported although git
#     detaches). Which prefix is unique depends on the option list of the git version (git 2.43.0 rejects --c as
#     ambiguous), so a rule would have to carry that list. Measured and filed as issue #77
#   - an option with a value that a git version other than 2.43.0 knows: the two value options and the short
#     letters are the ones git switch -h and git checkout -h print here; no other version was run
readme_push_main() {
  # issue #66: the fence rule (fence_run, fence_change) comes from FENCE_AWK, in front of the program
  awk "$FENCE_AWK"'
    function issep(t) { return (t == "&&" || t == "||" || t == "|" || t == ";" || t == "`" || t ~ /^#/) }
    # \047 is the single quote: the awk program itself stands in single quotes, so it cannot be written literally
    function bare(t) { gsub(/^["\047(]+|[.,:;!?)"\047]+$/, "", t); return t }
    { s = $0; sub(/\r+$/, "", s); L[NR] = s }
    END {
      fence = 0; onmain = 0; found = 0; block = 0
      for (r = 1; r <= NR; r = nx) {
        # issue #66 - the state lines of the fence and of the indented block, moved here from behind the join (the
        # comments on the indented block and on the indent of a fence line are still there). They read only L[r],
        # so nothing changes for them. The fence rule is the one of FENCE_AWK: outside a fenced block every fence
        # line opens one and its character and length are kept; inside, only a line of that character with a run
        # at least as long and nothing but blanks or tabs behind it closes it. Opening and closing clear the
        # state, as every fence line did before; a line that only looks like a fence line inside a block is
        # content and leaves the state as it is. A block that nothing closes lasts to the end of the file.
        if (fence_change(L[r])) {
          if (fence) fence = 0
          else { fence = 1; fch = FCH; flen = FLEN }
          onmain = 0; block = 0
        }
        else if (!fence) {
          if (L[r] ~ /^[ \t]*$/) { }
          else if (L[r] ~ /^(    | ? ? ?\t)/) { if (!block) onmain = 0; block = 1 }
          else { onmain = 0; block = 0 }
        }
        # one logical line: the physical lines r .. nx-1, joined where a line ends in a backslash
        n = 0; text = ""; nx = r
        do {
          s = L[nx]; cont = 0
          # Superseded by issue #49, kept as a comment - the fence test of the join had no limit on the indent:
          #   if (s ~ /\\$/ && nx < NR && L[nx + 1] !~ /^[ \t]*(```|~~~)/) {
          # A fence line has at most three blanks and no tab in front (see the state lines below); a line of three
          # backticks or tildes that is indented further is no fence, so a wrapped command is joined with it too.
          # Superseded by issue #66, kept as a comment - the fence test of the join did not know the open block:
          #   if (s ~ /\\$/ && nx < NR && L[nx + 1] !~ /^ ? ? ?(```|~~~)/) {
          # The next line ends the join only when it changes the fence state as it is at this line (fence_change):
          # outside a block every fence line, inside one only the line that closes it. A line of the other
          # character, a shorter run, or a run with text behind it is content there, and a wrapped command is
          # joined with it.
          if (s ~ /\\$/ && nx < NR && !fence_change(L[nx + 1])) {
            cont = 1; sub(/[ \t]*\\$/, "", s)
          }
          if (nx > r) sub(/^[ \t]+/, "", s)
          text = (nx == r) ? s : text " " s
          gsub(/`/, " ` ", s); gsub(/;/, " ; ", s)
          m = split(s, w, /[ \t]+/)
          for (k = 1; k <= m; k++) if (w[k] != "") { tok[++n] = w[k]; tl[n] = nx }
          nx++
        } while (cont)
        # Superseded by the three branches below (issue #32); the rule before, kept as a comment - outside a fence
        # the state was cleared at every line, so it never reached the second line of an indented code block:
        #   if (fence line) { fence = !fence; onmain = 0 }
        #   else if (!fence) onmain = 0
        # block = 1 while the lines read outside a fence are an indented code block: four blanks, or a tab after at
        # most three blanks, in front of the first physical line of the command. The state is kept from one such
        # line to the next and across an empty line (blanks and tabs only); it is cleared at the first indented
        # line after a line that was not (a switch to main in a line that is not indented lives for that line
        # only, as before) and at every line with text that is not indented that far.
        # Superseded by issue #49, kept as a comment - the fence test had no limit on the indent, so an indented
        # line of three backticks or tildes toggled the fence and cleared the state:
        #   if (L[r] ~ /^[ \t]*(```|~~~)/) { fence = !fence; onmain = 0; block = 0 }
        # A fence line has at most three blanks and no tab in front (the CommonMark rule). Indented by four blanks,
        # or by a tab after at most three blanks, such a line is read like any other: outside a fence it falls
        # into the indented-block branch below and keeps the state, inside a fence it is content and does not
        # close the fence.
        # Superseded by issue #66, kept as a comment - every fence line toggled, whatever had opened the block:
        #   if (L[r] ~ /^ ? ? ?(```|~~~)/) { fence = !fence; onmain = 0; block = 0 }
        #   else if (!fence) {
        #     if (L[r] ~ /^[ \t]*$/) { }
        #     else if (L[r] ~ /^(    | ? ? ?\t)/) { if (!block) onmain = 0; block = 1 }
        #     else { onmain = 0; block = 0 }
        #   }
        # These state lines now stand in front of the join, at the head of the loop (see there): the join asks
        # fence_change about the next line, and the answer has to be given with the state this line leaves.
        hit = 0
        for (i = 1; i < n && !hit; i++) {
          # the command word: git at the start of the word, after a character that is no part of a name ("git,
          # (git, `git), or after a slash (/usr/bin/git, ./git) - not legit, my-git, .git. Quotes at the end of
          # the word are dropped first (issue #33), so "git", \047git\047 and "/usr/bin/git" are read like git; a
          # quote in front of the word was no part of a name before. Only quotes: git) stays what it is.
          c = tok[i]; sub(/["\047]+$/, "", c)
          if (c !~ /(^|[^A-Za-z0-9_.\/-]|\/)git$/) continue
          k = i + 1
          while (k <= n && tok[k] ~ /^-/) {
            k += (tok[k] ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--config-env)$/) ? 2 : 1
          }
          if (k > n) continue
          cmd = tok[k]; ended = 0
          # issue #41 - the subcommand in quotes: push, switch or checkout between one pair of quotes (the same
          # quote in front and behind) is that subcommand, and the words after it are its arguments. Closing
          # punctuation behind the pair ends the command at the word, as it does behind the bare word (the last
          # word of a quoted command or of a subshell: sh -c \047git "push"\047). The quote in front is what tells
          # this from the rule below: push + quote with nothing in front closes a whole command.
          # Superseded by issue #24, kept as a comment - the two tests knew three subcommands; branch is the fourth:
          #   if (cmd ~ /^("(push|switch|checkout)"|\047(push|switch|checkout)\047)[.,:;!?)"\047]*$/) {
          #   else if (cmd ~ /^(push|switch|checkout)[.,:;!?)"\047]+$/) { ended = 1; cmd = bare(cmd) }
          if (cmd ~ /^("(push|switch|checkout|branch)"|\047(push|switch|checkout|branch)\047)[.,:;!?)"\047]*$/) {
            ended = (length(cmd) > length(bare(cmd)) + 2)
            cmd = bare(cmd)
          }
          # "push." / "push)" / "push" + quote in a sentence, a subshell or a quoted command: the command ends at the
          # word itself
          else if (cmd ~ /^(push|switch|checkout|branch)[.,:;!?)"\047]+$/) { ended = 1; cmd = bare(cmd) }
          if (cmd == "push") {
            pos = 0; tags = 0
            for (j = k + 1; j <= n && !ended && !hit; j++) {
              t = tok[j]
              if (issep(t)) break
              t = bare(t)
              if (t == "") continue
              if (t ~ /^-/) {
                if (t == "--all" || t == "--mirror" || t == "--branches") hit = 1
                else if (t == "--tags") tags = 1
                else if (t ~ /^(-o|--push-option|--receive-pack|--exec)$/ && j < n && !issep(tok[j + 1])) j++
                continue
              }
              pos++
              if (pos > 1) {
                sub(/^\+/, "", t)
                head = (t == "HEAD" || t == "@")
                sub(/^.*:/, "", t); sub(/^refs\/heads\//, "", t)
                if (t == "main" || (onmain && head)) hit = 1
              }
            }
            if (!hit && onmain && pos <= 1 && !tags) hit = 1
            if (hit) at = tl[i]
          } else if (cmd == "switch" || cmd == "checkout") {
            # issue #24 - two more things are read from the words of a switch or checkout. track: an option that makes
            # git derive the name of a new local branch from a remote branch (--track, -t, --track=<mode> and, as
            # measured with scripts/branch-after-probe.sh, --no-track too). nb: the word behind a new-branch option
            # (-c -C -b -B --create --force-create --orphan), wherever the option stands - behind the start point as
            # well (git switch origin/main -c feat/x).
            first = ""; paths = 0; detach = 0; track = 0; nb = ""; wantnb = 0; skipval = 0
            for (j = k + 1; j <= n && !ended; j++) {
              t = tok[j]
              if (issep(t)) break
              t = bare(t)
              if (t == "") continue
              if (t == "--") { paths = 1; break }
              # Superseded by issue #24, kept as a comment - of the options only --detach was read:
              #   if (t ~ /^-./) { if (t == "--detach" || t == "-d") detach = 1; continue }
              # Superseded by issue #75, kept as a comment - every option was tested as a whole word, so -ft was no
              # track option, -cmain no new-branch option, and the word behind --conflict was taken for the branch:
              #   if (t ~ /^-./) {
              #     if (t == "--detach" || t == "-d") detach = 1
              #     else if (t ~ /^(--track|--track=.*|-t|--no-track)$/) track = 1
              #     else if (t ~ /^(-c|-C|-b|-B|--create|--force-create|--orphan)$/) wantnb = 1
              #     continue
              #   }
              # issue #75 - an option word is read the way git reads it (git switch -h and git checkout -h of git
              # 2.43.0 are the list). A long option is split at its first "=": the name in front, the value behind.
              # A word of short options is read letter by letter: d is --detach, t is --track and takes the rest of
              # the word as its mode, c C b B take the rest of the word as the name of the new branch, or the next
              # word when nothing is left; every other letter (f m q l p 2 3) takes no value. --conflict and
              # --pathspec-from-file take their value as the next word, which is then no branch (skipval).
              if (t ~ /^-./) {
                if (t ~ /^--/) {
                  eq = index(t, "="); nm = eq ? substr(t, 1, eq - 1) : t; val = eq ? substr(t, eq + 1) : ""
                  if (nm == "--detach") detach = 1
                  else if (nm == "--track" || nm == "--no-track") track = 1
                  else if (nm ~ /^--(create|force-create|orphan)$/) {
                    if (!eq) wantnb = 1
                    else {
                      sub(/^["\047]+/, "", val)
                      if (nb == "") nb = val
                      if (first == "") first = val
                    }
                  }
                  else if (nm ~ /^--(conflict|pathspec-from-file)$/ && !eq) skipval = 1
                } else {
                  for (p = 2; p <= length(t); p++) {
                    ch = substr(t, p, 1)
                    if (ch == "d") detach = 1
                    else if (ch == "t") { track = 1; break }
                    else if (ch ~ /^[cCbB]$/) {
                      val = substr(t, p + 1); sub(/^["\047]+/, "", val)
                      if (val == "") wantnb = 1
                      else {
                        if (nb == "") nb = val
                        if (first == "") first = val
                      }
                      break
                    }
                  }
                }
                continue
              }
              if (skipval) { skipval = 0; continue }
              if (wantnb) { if (nb == "") nb = t; wantnb = 0 }
              if (first == "") first = t
            }
            # Superseded by issue #24, kept as a comment - the first word alone decided:
            #   if (detach) onmain = 0
            #   else if (!paths && first != "") onmain = (first == "main")
            # The branch that is checked out afterwards: the name behind a new-branch option when there is one; else,
            # with a track option, the part of the first word behind its first slash (refs/ and remotes/ in front are
            # dropped first, as git does), so <remote>/main is main and <remote>/topic/main is not; else the first
            # word. A track option in front of the bare word main keeps the verdict it had (git rejects the command).
            if (detach) onmain = 0
            else if (!paths && first != "") {
              if (nb != "") onmain = (nb == "main")
              else if (track) {
                tb = first; sub(/^refs\//, "", tb); sub(/^remotes\//, "", tb)
                onmain = (first == "main" || tb ~ /^[^\/]+\/main$/)
              }
              else onmain = (first == "main")
            }
          } else if (cmd == "branch") {
            # issue #24 - git branch -m / -M / --move renames a branch. One word behind the options: the current
            # branch gets that name, so the state is set by the name main and cleared by any other. Two words, old
            # and new: the text does not say whether old is the current branch. The new name main sets the state
            # (the usual case, git branch -m master main, renames the branch one stands on); the old name main with
            # another new name clears it; anything else leaves it. Without a move option git branch creates,
            # deletes, copies or lists and never changes what is checked out, so the state stays as it is.
            mv = 0; cnt = 0; last = ""; prev = ""
            for (j = k + 1; j <= n && !ended; j++) {
              t = tok[j]
              if (issep(t)) break
              t = bare(t)
              if (t == "") continue
              if (t ~ /^-./) { if (t ~ /^(-m|-M|--move)$/) mv = 1; continue }
              prev = last; last = t; cnt++
            }
            if (mv && cnt == 1) onmain = (last == "main")
            else if (mv && cnt == 2) {
              if (last == "main") onmain = 1
              else if (prev == "main") onmain = 0
            }
          }
        }
        if (hit) { print at ": " text; found = 1 }
      }
      exit found ? 0 : 1
    }
  ' "$1"
}

# tool_files ROOT — prints, each ended by a NUL byte and sorted by byte value, the path of every file install.sh
# copies from ROOT into a project (issue #25): agents/*.md, commands/*.md and every file of every skills/<name>/,
# hidden ones too, except the skill's own evals/ folder. The entries of a skill are taken the way install.sh takes
# them (three patterns, the entry named evals skipped), so an evals/ deeper inside a skill is read like install.sh
# installs it. Not printed: scripts/, .claude/ and README.md - they are not installed.
# A symlink to a file is printed by the path of the link, so its content is read: install.sh copies an agent or
# command with a plain cp, which copies what the link points to, and an entry of a skill with cp -r, which copies
# the link itself - on the machine of the install that link still leads to the same content. Not printed: a link
# that leads to no file.
# A symlink to a directory inside a skill is not entered here (cp -r copies that link, find does not go behind it),
# and since issue #51 it does not have to be: run_checks rejects every such link (skill_dir_links below), so a tree
# the gate accepts has no installed content behind one. Until then this comment listed the form as not read, and a
# push instruction in a file behind such a link passed check 7 (measured with the fixture tooldirlink).
# Superseded first form of this function (same branch, before the symlink cases toolagentlink and toolskilllink):
# the agents and commands loop also tested [ ! -L "$f" ] and the skills loop ran find "$e" -type f -print0, so a
# linked file was never read and a command behind it passed check 7.
tool_files() {
  local root="$1" f d e
  {
    for f in "$root"/agents/*.md "$root"/commands/*.md; do
      [ -f "$f" ] && printf '%s\0' "$f"
    done
    for d in "$root"/skills/*/; do
      [ -d "$d" ] || continue
      for e in "$d"* "$d".[!.]* "$d"..?*; do
        [ -e "$e" ] || continue
        [ "$(basename "$e")" = "evals" ] && continue
        while IFS= read -r -d '' f; do
          [ -f "$f" ] && printf '%s\0' "$f"
        done < <(find "$e" \( -type f -o -type l \) -print0)
      done
    done
  } | LC_ALL=C sort -z
}

# skill_dir_links ROOT — prints, each ended by a NUL byte and sorted by byte value, the path of every symlink to a
# directory below a skills/<name>/ of ROOT (issue #51), at any depth of what install.sh copies. The entries of a
# skill are taken the way tool_files and install.sh take them (three patterns, the entry named evals skipped), so a
# skill's own evals - a folder or a link - stays out: it is not installed. find does not follow a link, so each
# link is printed once and nothing behind it is walked; [ -d ] is true for a link that leads to a directory,
# wherever that directory is (outside the skill, outside the repo, or a folder of the same skill).
# Not printed: a symlink to a file (allowed, tool_files prints it and check 7 reads it), a link that leads nowhere,
# and a skills/<name> that is itself a link to a directory (install.sh and tool_files both go through it, so its
# files are installed as files and read).
skill_dir_links() {
  local root="$1" f d e
  {
    for d in "$root"/skills/*/; do
      [ -d "$d" ] || continue
      for e in "$d"* "$d".[!.]* "$d"..?*; do
        [ -e "$e" ] || continue
        [ "$(basename "$e")" = "evals" ] && continue
        while IFS= read -r -d '' f; do
          [ -d "$f" ] && printf '%s\0' "$f"
        done < <(find "$e" -type l -print0)
      done
    done
  } | LC_ALL=C sort -z
}

# push_main_readout [FILE...] — the option --push-main (issue #25): check 7 alone, as a readout. Runs
# readme_push_main over every FILE and prints one "FILE:LINE: command" line per report (FILE as it was given), then
# the last line "push-main: ok files=N" or "push-main: FOUND hits=K files=N". Returns 0 when nothing is reported, 1
# when something is, 2 when a FILE is no readable file - then nothing is read, so a readout never says ok about a
# list it read only in part.
# Without a FILE it reads what check 7 reads in the repo this file belongs to: README.md and the files of
# tool_files, named by their path below the repo root. Nothing to read there is exit 2 as well, not an ok.
push_main_readout() {
  local f out root="" strip="" hits=0 files=0
  local -a paths=()
  if [ "$#" -eq 0 ]; then
    root="$(cd -P "$(dirname "$SELF")/.." && pwd)" || { echo "gate.sh: --push-main: cannot resolve the repo root" >&2; return 2; }
    strip="$root/"
    [ -f "$root/README.md" ] && paths+=("$root/README.md")
    while IFS= read -r -d '' f; do paths+=("$f"); done < <(tool_files "$root")
    [ "${#paths[@]}" -gt 0 ] || { echo "gate.sh: --push-main: no README.md and no installed file in $root" >&2; return 2; }
  else
    paths=("$@")
  fi
  for f in "${paths[@]}"; do
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
      echo "gate.sh: --push-main: not a readable file: ${f#"$strip"}" >&2
      return 2
    fi
  done
  for f in "${paths[@]}"; do
    files=$((files + 1))
    while IFS= read -r out; do
      [ -n "$out" ] || continue
      printf '%s:%s\n' "${f#"$strip"}" "$out"
      hits=$((hits + 1))
    done < <(readme_push_main "$f")
  done
  if [ "$hits" -eq 0 ]; then
    echo "push-main: ok files=$files"
    return 0
  fi
  echo "push-main: FOUND hits=$hits files=$files"
  return 1
}

# fence_lines FILE — prints what the fence rule of FENCE_AWK finds in FILE that is more than a plain fenced block,
# one "LINE: kind: text" line each, in the order of the lines, then one last line "= BLOCKS LONG INNER UNCLOSED":
#   long     - the line opens a fenced block with a run of four or more characters
#   inner    - the line stands inside a fenced block, starts like a fence line and does not close it: the other
#              character, a shorter run, or text behind the run. A reader that toggles at every fence line (check 7
#              before issue #66) ends the block here; where a file has no such line, both readers see the same blocks
#   unclosed - the line opens a fenced block that nothing closes before the end of the file ("long, unclosed" when
#              it is both)
# Since issue #69 a line that starts with a run of backticks and carries a backtick behind the run is no fence line
# for fence_run. Outside a block it opens none and is not counted; inside a block it is content and is not named as
# an inner line either (before, it was: it started like a fence line for the rule of that time).
# Carriage returns at the end of a line are dropped first, as readme_push_main does.
fence_lines() {
  awk "$FENCE_AWK"'
    { s = $0; sub(/\r+$/, "", s)
      m = fence_run(s)
      if (!fence) {
        if (m) {
          fence = 1; fch = FCH; flen = FLEN; open = NR; blocks++
          if (m >= 4) { long++; kind[NR] = "long"; text[NR] = s }
          else text[NR] = s
        }
      } else if (m) {
        if (fence_change(s)) fence = 0
        else { inner++; kind[NR] = "inner"; text[NR] = s }
      }
    }
    END {
      if (fence) { unclosed++; kind[open] = (kind[open] != "") ? kind[open] ", unclosed" : "unclosed" }
      for (i = 1; i <= NR; i++) if (kind[i] != "") print i ": " kind[i] ": " text[i]
      print "= " (blocks + 0) " " (long + 0) " " (inner + 0) " " (unclosed + 0)
    }
  ' "$1"
}

# fence_readout [FILE...] — the option --fences (issue #66): the code fences of every FILE as the fence rule reads
# them, as a readout. Prints one "FILE:LINE: kind: text" line per line fence_lines names (FILE as it was given), then
# the last line "fences: files=N blocks=B long=L inner=I unclosed=U". Returns 0 when every FILE was read, whatever
# the counts - it is a count, not a verdict - and 2 when a FILE is no readable file; then nothing is read.
# Without a FILE it reads what check 7 reads in the repo this file belongs to: README.md and the files of
# tool_files, named by their path below the repo root. Nothing to read there is exit 2 as well.
# What it is for: before the fence rule changes, inner=0 over the files check 7 reads shows that the change moves
# no block there (the measurement issue #66 asks for first).
fence_readout() {
  local f out root="" strip="" files=0 blocks=0 long=0 inner=0 unclosed=0 b l i u
  local -a paths=()
  if [ "$#" -eq 0 ]; then
    root="$(cd -P "$(dirname "$SELF")/.." && pwd)" || { echo "gate.sh: --fences: cannot resolve the repo root" >&2; return 2; }
    strip="$root/"
    [ -f "$root/README.md" ] && paths+=("$root/README.md")
    while IFS= read -r -d '' f; do paths+=("$f"); done < <(tool_files "$root")
    [ "${#paths[@]}" -gt 0 ] || { echo "gate.sh: --fences: no README.md and no installed file in $root" >&2; return 2; }
  else
    paths=("$@")
  fi
  for f in "${paths[@]}"; do
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
      echo "gate.sh: --fences: not a readable file: ${f#"$strip"}" >&2
      return 2
    fi
  done
  for f in "${paths[@]}"; do
    files=$((files + 1))
    while IFS= read -r out; do
      case "$out" in
        "= "*)
          read -r b l i u <<< "${out#= }"
          blocks=$((blocks + b)); long=$((long + l)); inner=$((inner + i)); unclosed=$((unclosed + u))
          ;;
        "") ;;
        *) printf '%s:%s\n' "${f#"$strip"}" "$out" ;;
      esac
    done < <(fence_lines "$f")
  done
  echo "fences: files=$files blocks=$blocks long=$long inner=$inner unclosed=$unclosed"
  return 0
}

run_checks() {
  local root="$1" f
  FAILS=0

  # check 0 (issue #29): the root is a checkout of this repo. Without install.sh and README.md nearly every check
  # below is skipped or has nothing to read, so an empty directory - or the directory above a link to this file -
  # passed with nothing checked. Such a root is rejected here, and nothing in it is read or run.
  [ -f "$root/install.sh" ] || fail "not a checkout of this repo: no install.sh in $root"
  [ -f "$root/README.md" ] || fail "not a checkout of this repo: no README.md in $root"
  [ "$FAILS" -eq 0 ] || return 1

  for f in "$root/install.sh" "$root"/scripts/*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" 2>/dev/null || fail "bash -n ${f#"$root"/}"
  done

  for f in "$root"/agents/*.md "$root"/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    frontmatter_ok "$f" "name description" || fail "frontmatter name/description: ${f#"$root"/}"
  done
  for f in "$root"/commands/*.md; do
    [ -f "$f" ] || continue
    [ -s "$f" ] || fail "empty command file: ${f#"$root"/}"
  done

  local checker="$AGENT_CHECKER" out
  if [ -d "$root/.claude/agents" ] && [ -f "$checker" ]; then
    # issue #21: the checker looks up the paths an agent file names in its working directory, so it is started in
    # the root that is checked. The $( ) is a subshell: the working directory of the gate's caller stays as it was.
    if ! out="$(cd "$root" && python3 "$checker" .claude/agents --sections "" --model sonnet,opus,haiku,inherit 2>&1)"; then
      fail "agent-file-check on .claude/agents"
      printf '%s\n' "$out"
    fi
  else
    echo "note: agent-file-check skipped (no .claude/agents or no store)"
  fi

  if [ -f "$root/install.sh" ]; then
    local tmp w g
    tmp="$(mktemp -d)"
    if bash "$root/install.sh" "$tmp/dest" >/dev/null 2>&1; then
      w="$(find "$root/agents" -maxdepth 1 -name '*.md' | wc -l)/$(find "$root/commands" -maxdepth 1 -name '*.md' | wc -l)/$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      g="$(find "$tmp/dest/agents" -maxdepth 1 -name '*.md' | wc -l)/$(find "$tmp/dest/commands" -maxdepth 1 -name '*.md' | wc -l)/$(find "$tmp/dest/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      [ "$w" = "$g" ] || fail "install.sh counts agents/commands/skills want $w got $g"
      # issue #6: counts alone do not prove content - the fresh install must be in step with the source file by
      # file, agents and commands included (the diff below reads skills/ only). install-status.sh is read from the
      # directory of this file; a gate file that stands alone says so instead of passing in silence.
      local stater
      stater="$(dirname "$SELF")/install-status.sh"
      if [ -f "$stater" ]; then
        if ! out="$(bash "$stater" --source "$root" "$tmp/dest" 2>&1)"; then
          fail "fresh install is not in step with the source (scripts/install-status.sh)"
          printf '%s\n' "$out"
        fi
      else
        echo "note: install-status skipped (no install-status.sh next to gate.sh)"
      fi
      # issue #8 — what the counts do not see. Fresh destination: every entry of a skill arrives (hidden ones
      # too) except its evals/. Destination that already holds skills/<name>/evals/own.json for every skill:
      # after the install each own.json is still there and nothing was added next to it.
      local n own all
      diff -r -x evals "$root/skills" "$tmp/dest/skills" >/dev/null 2>&1 || fail "install.sh did not copy every entry of every skill (evals/ aside, hidden entries included)"
      [ -z "$(find "$tmp/dest/skills" -mindepth 2 -maxdepth 2 -name evals)" ] || fail "install.sh installed a skill's evals/ folder (evals are not installed)"
      for f in "$root"/skills/*/; do
        [ -d "$f" ] || continue
        mkdir -p "$tmp/kept/skills/$(basename "$f")/evals"
        printf 'own\n' > "$tmp/kept/skills/$(basename "$f")/evals/own.json"
      done
      bash "$root/install.sh" "$tmp/kept" >/dev/null 2>&1 || fail "install.sh into a destination that already has evals/ folders"
      n="$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      own="$(find "$tmp/kept/skills" -mindepth 3 -maxdepth 3 -path '*/evals/own.json' | wc -l)"
      all="$(find "$tmp/kept/skills" -mindepth 3 -maxdepth 3 -path '*/evals/*' | wc -l)"
      [ "$own" = "$n" ] || fail "install.sh removed an evals/ folder the destination already had (issue #8): $own of $n own.json left"
      [ "$all" = "$own" ] || fail "install.sh wrote into an evals/ folder the destination already had (issue #8): $all entries, $own of them own.json"
    else
      fail "install.sh into temp dir"
    fi
    rm -rf "$tmp"
    # a non-comment "${1:-something}" is a default destination: a bare ./install.sh would write somewhere unasked
    if grep -v '^[[:space:]]*#' "$root/install.sh" | grep -q -E '\$\{1:-[^}]'; then
      fail "install.sh has a default destination (issue #4: the destination must be given)"
    fi
  fi

  local lister
  lister="$(dirname "$SELF")/readme-listing-check.sh"
  if [ -f "$root/README.md" ] && [ -f "$lister" ]; then
    if ! out="$(bash "$lister" "$root" 2>&1)"; then
      fail "README.md listing (scripts/readme-listing-check.sh)"
      printf '%s\n' "$out"
    fi
  fi

  # check 7: README.md must not instruct a git push whose target is main (issue #16)
  if [ -f "$root/README.md" ]; then
    while IFS= read -r out; do
      [ -n "$out" ] || continue
      fail "README.md:${out%%:*}: git push to main (issue #16: main changes only through a merged pull request):${out#*:}"
    done < <(readme_push_main "$root/README.md")
  fi
  # check 7, second part (issue #25): the same reader over every file install.sh copies into a project (tool_files:
  # agents/*.md, commands/*.md, every file of a skill except its evals/). An instruction there is repeated in every
  # session of the projects it is installed into - a wider reach than the README has. The FAIL line names the file
  # by its path below the root.
  # There is no exceptions file, on purpose: the readout over the tree of 2026-10-06 (scripts/gate.sh --push-main,
  # 18 installed files) reported nothing, so there is nothing to except. A command that is right in the repo it is
  # installed into (which push rule holds in hl_claw_bot is the open decision of issue #47) gets a declared
  # exception - a file with one line per exception and its reason, like scripts/skill-drift-declared.txt - when
  # the first one exists; until then such a command is reworded as a sentence or the gate stays red.
  # issue #51: the reader below does not go behind a symlink to a directory inside a skill, and install.sh copies
  # such a link as a link - on the machine of the install it still leads to its files, in a project elsewhere it
  # leads nowhere. Either way the skill does not carry its own files, so the link itself is rejected: one FAIL per
  # link (skill_dir_links), named by its path below the root and by the target as the link carries it. With that, a
  # tree this check accepts has no installed file it did not read. A symlink to a file stays allowed and is read.
  while IFS= read -r -d '' f; do
    fail "${f#"$root"/} -> $(readlink "$f"): symlink to a directory inside a skill (issue #51: install.sh copies the link and not the files behind it, and check 7 does not read them - a skill carries its own files)"
  done < <(skill_dir_links "$root")
  while IFS= read -r -d '' f; do
    while IFS= read -r out; do
      [ -n "$out" ] || continue
      fail "${f#"$root"/}:${out%%:*}: git push to main in a file install.sh installs (issue #25: it is repeated in every session of the projects it is installed into):${out#*:}"
    done < <(readme_push_main "$f")
  done < <(tool_files "$root")
  [ "$FAILS" -eq 0 ]
}

# fixture_installer FILE SKILL_COPY — writes a minimal installer for the selftest whose skills loop runs
# SKILL_COPY; in it $d is the skill's source dir (with trailing slash) and $o the skill's destination dir
fixture_installer() {
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'DEST="$1"' \
    'S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' \
    'mkdir -p "$DEST/agents" "$DEST/commands" "$DEST/skills"' \
    'cp "$S"/agents/*.md "$DEST/agents/"' \
    'cp "$S"/commands/*.md "$DEST/commands/"' \
    'for d in "$S"/skills/*/; do' \
    '  o="$DEST/skills/$(basename "$d")"' \
    '  mkdir -p "$o"' \
    "  $2" \
    'done' > "$1"
}

# push_block WANT LINE... — selftest helper for check 7 (issue #18): writes the LINEs into a fixture of its own and
# compares the line numbers readme_push_main reports with WANT ("" = nothing reported, "3" = line 3, "3 4" = both).
# Prints the fixture and returns 1 on a difference.
push_block() {
  local want="$1" got="" out f
  shift
  f="$(mktemp)"
  printf '%s\n' "$@" > "$f"
  while IFS= read -r out; do
    got="$got${got:+ }${out%%:*}"
  done < <(readme_push_main "$f")
  rm -f "$f"
  [ "$got" = "$want" ] && return 0
  echo "selftest FAIL: check 7 block case, reported line(s) want '$want' got '$got':"
  printf '    | %s\n' "$@"
  return 1
}

# fixture_readme FILE — writes the README of the selftest fixtures: it names agent a, command c, skill x and
# install.sh, so check 6 is green on the good fixture. 19 lines; the push cases append their block at line 20.
fixture_readme() {
  printf '# f\n\n```\nf/\n├── agents/\n│   └── a.md\n├── commands/\n│   └── c.md\n├── skills/\n│   └── x/\n└── install.sh\n```\n\n### `a`\n\n### `/c`\n\n### `/x`\n' > "$1"
}

# link_case WHAT DIR PATH WANT [TEXT] — selftest helper (issue #29): starts the gate file PATH with bash in the
# directory DIR. WANT is "<last output line> exit=N"; with TEXT the output must carry that text as well, which
# tells a rejection for the real root's reason from a rejection of some other root. Prints the difference and
# returns 1 when it does not hold.
link_case() {
  local out code got
  out="$(cd "$2" && bash "$3" 2>&1)"
  code=$?
  got="${out##*$'\n'} exit=$code"
  if [ "$got" != "$4" ]; then
    echo "selftest FAIL: $1: want '$4' got '$got'"
    return 1
  fi
  if [ -n "${5:-}" ] && ! printf '%s\n' "$out" | grep -q -F -- "$5"; then
    echo "selftest FAIL: $1: the output lacks '$5':"
    printf '%s\n' "$out"
    return 1
  fi
  return 0
}

# install_link_case WHAT DIR PATH DEST WANT — selftest helper (issue #35): starts the installer file PATH with bash
# in the directory DIR, with the destination DEST (a directory below the selftest's temp dir that does not exist
# yet). The start must end with exit 0, and DEST must then hold exactly the files WANT (one "./path" per line,
# sorted) - the files of the repo the installer file belongs to, not those of the directory above the link.
# Prints the difference and returns 1 when it does not hold.
install_link_case() {
  local out code got
  out="$(cd "$2" && bash "$3" "$4" 2>&1)"
  code=$?
  if [ "$code" -ne 0 ]; then
    echo "selftest FAIL: $1: exit $code, want 0; last line: ${out##*$'\n'}"
    return 1
  fi
  got="$(cd "$4" && find . -type f | LC_ALL=C sort)"
  if [ "$got" != "$5" ]; then
    echo "selftest FAIL: $1: installed files differ from those of the installer's own repo; got:"
    printf '    | %s\n' $got
    return 1
  fi
  return 0
}

# install_count_case WHAT DIR SRC DEST AGENTS COMMANDS SKILLS WANT — selftest helper (issue #54): starts the
# installer file SRC/install.sh with bash in the directory DIR, with the destination DEST (a directory below the
# selftest's temp dir that does not exist yet). The line before the last of its output is the one a session reads to
# decide that the install was complete, so it has to say what was copied. Wanted: exit 0, nothing on stderr, the
# line before the last is exactly "Done. Installed AGENTS agents, COMMANDS commands, SKILLS skills.", the output
# carries AGENTS "[agent]", COMMANDS "[command]" and SKILLS "[skill]" lines, and DEST holds exactly the files WANT
# (one "./path" per line, sorted by byte value). Before issue #54 the three numbers came from ls over the source
# folders: an entry of agents/ or commands/ that is no *.md was counted and not installed.
# Prints one "selftest FAIL" line with what differs below it and returns 1 when it does not hold.
install_count_case() {
  local out err code rest line want got na nc ns why=""
  err="$(mktemp)"
  out="$(cd "$2" && bash "$3/install.sh" "$4" 2>"$err")"
  code=$?
  [ "$code" -eq 0 ] || why="$why"$'\n'"    exit $code, want 0"
  [ ! -s "$err" ] || why="$why"$'\n'"    stderr is not empty, first line: $(head -n 1 "$err")"
  rm -f "$err"
  want="Done. Installed $5 agents, $6 commands, $7 skills."
  rest="${out%$'\n'*}"
  line="${rest##*$'\n'}"
  [ "$line" = "$want" ] || why="$why"$'\n'"    the line before the last: want '$want' got '$line'"
  na="$(printf '%s\n' "$out" | grep -c '^  \[agent\] ')"
  nc="$(printf '%s\n' "$out" | grep -c '^  \[command\] ')"
  ns="$(printf '%s\n' "$out" | grep -c '^  \[skill\] ')"
  [ "$na $nc $ns" = "$5 $6 $7" ] || why="$why"$'\n'"    [agent] / [command] / [skill] lines printed: want '$5 $6 $7' got '$na $nc $ns'"
  got="$(cd "$4" 2>/dev/null && find . -type f | LC_ALL=C sort)"
  if [ "$got" != "$8" ]; then
    why="$why"$'\n'"    the destination holds other files than wanted; got:"$'\n'"$(printf '%s\n' "$got" | sed 's/^/      | /')"
  fi
  [ -z "$why" ] && return 0
  echo "selftest FAIL: $1:$why"
  return 1
}

# install_nosource_case WHAT DIR SRC DEST MISSING — selftest helper (issue #45): starts the installer file
# SRC/install.sh with bash in the directory DIR, with the destination DEST. SRC lacks the folders MISSING (as the
# installer names them, say "agents/, commands/, skills/"), and neither DEST nor the directory above it exists.
# Wanted: exit 1, exactly one line of output - the one that names SRC and MISSING and ends with
# "(nothing installed)" - and afterwards neither DEST nor the directory above it exists. Before issue #45 the
# installer made DEST/agents, DEST/commands and DEST/skills first and then stopped with a cp error on its source.
# Prints what differs and returns 1 when it does not hold.
install_nosource_case() {
  local out code src want bad=0
  src="$(cd -P "$3" && pwd)"
  want="install.sh: not a checkout of tgc-dev-tools: no $5 in $src (nothing installed)"
  out="$(cd "$2" && bash "$3/install.sh" "$4" 2>&1)"
  code=$?
  if [ "$code" -ne 1 ]; then
    echo "selftest FAIL: $1: exit $code, want 1"
    bad=1
  fi
  if [ "$out" != "$want" ]; then
    echo "selftest FAIL: $1: want the one line '$want', got:"
    printf '%s\n' "$out" | while IFS= read -r line; do printf '    | %s\n' "$line"; done
    bad=1
  fi
  if [ -e "$4" ] || [ -e "$(dirname "$4")" ]; then
    echo "selftest FAIL: $1: the destination exists after an install that failed; it holds:"
    find "$(dirname "$4")" | LC_ALL=C sort | while IFS= read -r line; do printf '    | %s\n' "$line"; done
    bad=1
  fi
  return "$bad"
}

# install_empty_case WHAT DIR SRC DEST WANT — selftest helper (issue #53): starts the installer file
# SRC/install.sh with bash in the directory DIR, with the destination DEST, which does not exist. SRC has agents/,
# commands/ and skills/ beside the installer, and at least one of the three holds nothing to install. An empty
# folder means "nothing of that kind to install" (the decision of issue #53), so wanted is: exit 0, no line of cp
# in the output (stdout and stderr together), no entry named "*" anywhere below DEST, and below DEST exactly the
# entries WANT (one "./path" per line, sorted by byte value, folders included) - what the source had is installed
# and nothing else is there. Before issue #53 the unmatched pattern of a loop stayed as typed: cp stopped the
# install half way (exit 1), or - with an empty skills/ - it ended with exit 0 and a skill directory named "*".
# Prints one "selftest FAIL" line with what differs below it and returns 1 when it does not hold.
install_empty_case() {
  local out code got star why=""
  out="$(cd "$2" && bash "$3/install.sh" "$4" 2>&1)"
  code=$?
  [ "$code" -eq 0 ] || why="$why"$'\n'"    exit $code, want 0"
  if printf '%s\n' "$out" | grep -q '^cp: '; then
    why="$why"$'\n'"    cp reported an error: $(printf '%s\n' "$out" | grep -m1 '^cp: ')"
  fi
  star="$(find "$4" -name '\*' 2>/dev/null | LC_ALL=C sort)"
  [ -z "$star" ] || why="$why"$'\n'"    an entry named * in the destination: $star"
  got="$(cd "$4" 2>/dev/null && find . -mindepth 1 | LC_ALL=C sort)"
  if [ "$got" != "$5" ]; then
    why="$why"$'\n'"    the destination holds other entries than wanted; want:"$'\n'"$(printf '%s\n' "$5" | sed 's/^/      | /')"
    why="$why"$'\n'"    got:"$'\n'"$(printf '%s\n' "$got" | sed 's/^/      | /')"
  fi
  [ -z "$why" ] && return 0
  echo "selftest FAIL: $1:$why"
  return 1
}

# push_main_case WHAT DIR GATE WANT_EXIT WANT_OUT [ARG...] — selftest helper (issue #25): starts the gate file GATE
# with bash in the directory DIR as "GATE --push-main ARG...". The exit code must be WANT_EXIT and the whole output
# (stdout and stderr together) must be WANT_OUT, line for line. Prints both and returns 1 when it does not hold.
push_main_case() {
  local what="$1" dir="$2" gate="$3" wantcode="$4" want="$5" out code
  shift 5
  out="$(cd "$dir" && bash "$gate" --push-main "$@" 2>&1)"
  code=$?
  if [ "$code" -ne "$wantcode" ] || [ "$out" != "$want" ]; then
    echo "selftest FAIL: --push-main, $what: want exit $wantcode and"
    printf '%s\n' "$want" | sed 's/^/    | /'
    echo "  got exit $code and"
    printf '%s\n' "$out" | sed 's/^/    | /'
    return 1
  fi
  return 0
}

# fences_case WHAT DIR GATE WANT_EXIT WANT_OUT [ARG...] — selftest helper (issue #66): starts the gate file GATE
# with bash in the directory DIR as "GATE --fences ARG...". The exit code must be WANT_EXIT and the whole output
# (stdout and stderr together) must be WANT_OUT, line for line. Prints both and returns 1 when it does not hold.
fences_case() {
  local what="$1" dir="$2" gate="$3" wantcode="$4" want="$5" out code
  shift 5
  out="$(cd "$dir" && bash "$gate" --fences "$@" 2>&1)"
  code=$?
  if [ "$code" -ne "$wantcode" ] || [ "$out" != "$want" ]; then
    echo "selftest FAIL: --fences, $what: want exit $wantcode and"
    printf '%s\n' "$want" | sed 's/^/    | /'
    echo "  got exit $code and"
    printf '%s\n' "$out" | sed 's/^/    | /'
    return 1
  fi
  return 0
}

# tool_file_case WHAT ROOT WANT — selftest helper (check 7, issue #25): run_checks on the fixture ROOT must fail, and
# its FAIL lines must be exactly WANT - one line that names the file below ROOT, the line and the command. So the
# fixture is rejected by check 7 for that file and by nothing else. Prints the difference and returns 1 otherwise.
# A fourth argument names the issue of the case in the "accepted" line (default #25); the directory link cases of
# issue #51 pass it, and one of them passes a WANT of two lines.
tool_file_case() {
  local out got
  if out="$(run_checks "$2" 2>&1)"; then
    echo "selftest FAIL: $1 accepted (issue ${4:-#25})"
    return 1
  fi
  got="$(printf '%s\n' "$out" | grep '^FAIL: ')"
  if [ "$got" != "$3" ]; then
    echo "selftest FAIL: $1: want exactly this FAIL line"
    printf '%s\n' "$3" | sed 's/^/    | /'
    echo "  got"
    printf '%s\n' "$got" | sed 's/^/    | /'
    return 1
  fi
  return 0
}

# selftest_run CASES — runs the function CASES (the cases of the selftest), passes its output through as it comes
# and then prints the last line of the selftest (issue #67): "selftest ok" and returns 0 when CASES ended with 0 and
# printed no line that starts with "selftest FAIL:"; otherwise "selftest FAILED fail_lines=N" and returns 1, N being
# the number of those lines. Before, the cases printed "selftest ok" themselves and nothing in its place on a red
# run, so the last line of a red run was a line of the last failed case (for a block case a line of its fixture).
# The line is printed here and not at the end of the cases, because CASES runs as one end of a pipe: it is there as
# well when the cases stop before their end (an unset variable under set -u), and a "selftest FAIL:" line of a case
# that did not set its return code no longer stands above "selftest ok". The count is read from the output, so a
# case is written as before: print "selftest FAIL: ..." and set rc=1.
selftest_run() {
  local log code n
  log="$(mktemp)"
  "$1" | tee "$log"
  code="${PIPESTATUS[0]}"
  n="$(grep -c '^selftest FAIL:' "$log" 2>/dev/null)"
  n="${n:-0}"
  rm -f "$log"
  if [ "$code" -eq 0 ] && [ "$n" -eq 0 ]; then
    echo "selftest ok"
    return 0
  fi
  echo "selftest FAILED fail_lines=$n"
  return 1
}

# last_line_case WHAT CASES WANT_EXIT LINE... — selftest helper (issue #67): selftest_run over the function CASES
# must end with WANT_EXIT and print exactly the LINEs on stdout. Prints both and returns 1 when it does not hold.
last_line_case() {
  local what="$1" cases="$2" wantcode="$3" out code want
  shift 3
  out="$(selftest_run "$cases" 2>/dev/null)"
  code=$?
  want="$(printf '%s\n' "$@")"
  if [ "$code" -ne "$wantcode" ] || [ "$out" != "$want" ]; then
    echo "selftest FAIL: last line of the selftest, $what: want exit $wantcode and"
    printf '%s\n' "$want" | sed 's/^/    | /'
    echo "  got exit $code and"
    printf '%s\n' "$out" | sed 's/^/    | /'
    return 1
  fi
  return 0
}

selftest() {
  local t rc=0
  t="$(mktemp -d)"
  mkdir -p "$t/good/agents" "$t/good/commands" "$t/good/skills/x" "$t/bad/agents" "$t/bad/commands" "$t/bad/skills"
  printf -- '---\nname: a\ndescription: d\n---\nbody\n' > "$t/good/agents/a.md"
  printf 'cmd\n' > "$t/good/commands/c.md"
  printf -- '---\nname: x\ndescription: d\n---\nbody\n' > "$t/good/skills/x/SKILL.md"
  # empty / noinstall / noreadme (check 0, issue #29): a directory with nothing in it, the good fixture without
  # install.sh and the good fixture without README.md -> each rejected as "not a checkout of this repo", naming
  # exactly what is missing. Before issue #29 the first passed with nothing checked and the third was the good
  # fixture itself. noinstall and noreadme are copies of the good fixture taken while it is being put together.
  local out0
  mkdir -p "$t/empty"
  cp -r "$t/good" "$t/noinstall"
  fixture_readme "$t/noinstall/README.md"
  cp "$(dirname "$SELF")/../install.sh" "$t/good/install.sh"
  cp -r "$t/good" "$t/noreadme"
  fixture_readme "$t/good/README.md"
  out0="$(run_checks "$t/empty" 2>&1)" && { echo "selftest FAIL: empty directory accepted (issue #29)"; rc=1; }
  printf '%s\n' "$out0" | grep -q 'FAIL: not a checkout of this repo: no install.sh in ' || { echo "selftest FAIL: empty directory not rejected for the missing install.sh"; rc=1; }
  printf '%s\n' "$out0" | grep -q 'FAIL: not a checkout of this repo: no README.md in ' || { echo "selftest FAIL: empty directory not rejected for the missing README.md"; rc=1; }
  out0="$(run_checks "$t/noinstall" 2>&1)" && { echo "selftest FAIL: root without install.sh accepted (issue #29)"; rc=1; }
  [ "$out0" = "FAIL: not a checkout of this repo: no install.sh in $t/noinstall" ] || { echo "selftest FAIL: root without install.sh, want exactly the line for install.sh, got: $out0"; rc=1; }
  out0="$(run_checks "$t/noreadme" 2>&1)" && { echo "selftest FAIL: root without README.md accepted (issue #29)"; rc=1; }
  [ "$out0" = "FAIL: not a checkout of this repo: no README.md in $t/noreadme" ] || { echo "selftest FAIL: root without README.md, want exactly the line for README.md, got: $out0"; rc=1; }
  # bad: since check 0 it carries the README too, so it is still checks 1 and 2 that reject it - and they are named
  printf 'no frontmatter\n' > "$t/bad/agents/a.md"
  printf 'echo "unterminated\n' > "$t/bad/install.sh"
  fixture_readme "$t/bad/README.md"
  run_checks "$t/good" >/dev/null || { echo "selftest FAIL: good fixture rejected"; rc=1; }
  run_checks "$t/bad" >/dev/null && { echo "selftest FAIL: bad fixture accepted"; rc=1; }
  out0="$(run_checks "$t/bad" 2>&1)"
  printf '%s\n' "$out0" | grep -q -x 'FAIL: bash -n install.sh' || { echo "selftest FAIL: bad fixture not rejected by check 1 (bash -n install.sh)"; rc=1; }
  printf '%s\n' "$out0" | grep -q -x 'FAIL: frontmatter name/description: agents/a.md' || { echo "selftest FAIL: bad fixture not rejected by check 2 (frontmatter of agents/a.md)"; rc=1; }
  # default: good fixture whose install.sh carries a default destination again -> rejected (check 5)
  cp -r "$t/good" "$t/default"
  printf 'DEST="${1:-/nonexistent/.claude}"\n' >> "$t/default/install.sh"
  run_checks "$t/default" >/dev/null && { echo "selftest FAIL: default destination accepted"; rc=1; }
  # Superseded by the tamper block below (same fixture, and the reason for the rejection is asserted too); the older
  # assertion of this branch, kept as a comment when main was merged in:
  #   run_checks "$t/tamper" >/dev/null && { echo "selftest FAIL: altered install accepted"; rc=1; }
  # tamper: good fixture whose install.sh installs every file but alters one agent -> the counts match and the
  # skills are complete, the content is not what the source has -> rejected, and for that reason (check 4, issue #6)
  cp -r "$t/good" "$t/tamper"
  printf 'printf "altered\\n" >> "$DEST/agents/a.md"\n' >> "$t/tamper/install.sh"
  out0="$(run_checks "$t/tamper" 2>&1)" && { echo "selftest FAIL: altered install accepted"; rc=1; }
  printf '%s\n' "$out0" | grep -q -x 'FAIL: fresh install is not in step with the source (scripts/install-status.sh)' || { echo "selftest FAIL: tamper not rejected for the altered file"; rc=1; }
  printf '%s\n' "$out0" | grep -q -x 'DIFFERS  agents/a.md' || { echo "selftest FAIL: tamper output does not name the altered file"; rc=1; }
  # withevals: good fixture whose skill carries evals/ and a hidden entry -> accepted; a fresh install of it has
  # the hidden entry and no evals/ (check 4, issue #8)
  local out
  cp -r "$t/good" "$t/withevals"
  mkdir -p "$t/withevals/skills/x/evals"
  printf '{}\n' > "$t/withevals/skills/x/evals/evals.json"
  printf 'keep\n' > "$t/withevals/skills/x/.keep"
  run_checks "$t/withevals" >/dev/null || { echo "selftest FAIL: fixture with evals/ and a hidden entry rejected"; rc=1; }
  bash "$t/withevals/install.sh" "$t/withevals-dest" >/dev/null 2>&1
  [ -f "$t/withevals-dest/skills/x/.keep" ] || { echo "selftest FAIL: hidden entry of a skill not installed"; rc=1; }
  [ ! -e "$t/withevals-dest/skills/x/evals" ] || { echo "selftest FAIL: evals/ of a skill installed"; rc=1; }
  # evalsrm / evalscopied / nohidden: the same fixture with an installer that (a) copies the whole skill dir and
  # then removes evals/ in the destination - the behaviour before issue #8, (b) copies evals/ along, (c) skips
  # evals/ but drops hidden entries -> each rejected, and for its own reason (check 4)
  cp -r "$t/withevals" "$t/evalsrm"
  fixture_installer "$t/evalsrm/install.sh" 'cp -r "$d." "$o/"; rm -rf "$o/evals"'
  out="$(run_checks "$t/evalsrm" 2>&1)" && { echo "selftest FAIL: installer that removes the destination's evals/ accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q 'removed an evals/ folder the destination already had (issue #8)' || { echo "selftest FAIL: evalsrm not rejected for the removed evals/"; rc=1; }
  cp -r "$t/withevals" "$t/evalscopied"
  fixture_installer "$t/evalscopied/install.sh" 'cp -r "$d." "$o/"'
  out="$(run_checks "$t/evalscopied" 2>&1)" && { echo "selftest FAIL: installer that installs evals/ accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q "installed a skill's evals/ folder" || { echo "selftest FAIL: evalscopied not rejected for the installed evals/"; rc=1; }
  cp -r "$t/withevals" "$t/nohidden"
  fixture_installer "$t/nohidden/install.sh" 'for e in "$d"*; do [ "$(basename "$e")" = evals ] || cp -r "$e" "$o/"; done'
  out="$(run_checks "$t/nohidden" 2>&1)" && { echo "selftest FAIL: installer that drops hidden entries accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q 'did not copy every entry of every skill' || { echo "selftest FAIL: nohidden not rejected for the missing hidden entry"; rc=1; }
  # listed / drift: good fixture with a README that names everything -> accepted, one that names nothing -> rejected (check 6)
  # (since issue #29 the good fixture carries that README already - check 0 wants one; it is written again here so
  # that this case does not depend on it)
  cp -r "$t/good" "$t/listed"
  fixture_readme "$t/listed/README.md"
  run_checks "$t/listed" >/dev/null || { echo "selftest FAIL: listed fixture rejected"; rc=1; }
  cp -r "$t/good" "$t/drift"
  printf '# f\n\nnothing listed, install.sh\n' > "$t/drift/README.md"
  run_checks "$t/drift" >/dev/null && { echo "selftest FAIL: README drift accepted"; rc=1; }
  # pushmain / pushrefspec / pushbranch: the listed fixture (check 6 green) plus a push instruction in its README, so
  # only check 7 decides. The two rejected ones must name the line (the block starts at line 20, the command is 21).
  local out line
  cp -r "$t/listed" "$t/pushmain"
  printf '\n```bash\ngit push origin main\n```\n' >> "$t/pushmain/README.md"
  out="$(run_checks "$t/pushmain")"
  case "$out" in
    *"FAIL: README.md:21: git push to main"*) ;;
    *) echo "selftest FAIL: README with 'git push origin main' accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushrefspec"
  printf '\n```bash\ngit push origin HEAD:main\n```\n' >> "$t/pushrefspec/README.md"
  out="$(run_checks "$t/pushrefspec")"
  case "$out" in
    *"FAIL: README.md:21: git push to main"*) ;;
    *) echo "selftest FAIL: README with 'git push origin HEAD:main' accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushbranch"
  printf '\nThe change reaches `main` through a pull request, never by a push to `main`:\n\n```bash\ngit push -u origin feat/x\n```\n' >> "$t/pushbranch/README.md"
  run_checks "$t/pushbranch" >/dev/null || { echo "selftest FAIL: README with 'git push -u origin feat/x' rejected"; rc=1; }
  # line cases for check 7, straight at readme_push_main: 14 lines it must report, 15 it must leave alone. Since
  # issue #30 each list has one line that calls git by its path, one with the ref in single quotes and one that ends
  # in a carriage return (a file saved with CRLF line endings). A here-document line cannot carry a carriage return,
  # so that pair is written with printf right below its list.
  while IFS= read -r line; do
    printf '%s\n' "$line" > "$t/line.md"
    readme_push_main "$t/line.md" >/dev/null || { echo "selftest FAIL: push to main not seen: $line"; rc=1; }
  done <<'EOF'
git push origin main
git push -u origin main
git push origin HEAD:main
git push origin feat/x:main
git push --force origin +main
git push origin refs/heads/main
git push origin :main
git push origin --delete main
git push origin feat/x main
git fetch origin && git push origin main
Then run `git push origin main`.
/usr/bin/git push origin main
git push origin 'main'
EOF
  printf 'git push origin main\r\n' > "$t/line.md"
  readme_push_main "$t/line.md" >/dev/null || { echo "selftest FAIL: push to main not seen: git push origin main + carriage return"; rc=1; }
  while IFS= read -r line; do
    printf '%s\n' "$line" > "$t/line.md"
    readme_push_main "$t/line.md" >/dev/null && { echo "selftest FAIL: no push to main, but reported: $line"; rc=1; }
  done <<'EOF'
git push -u origin feat/x
git push origin maintenance
git push origin feat/main-menu
git push origin main:feat/x
git push main feat/x
git push origin feat/x && git switch main
git push origin feat/x; git switch main
git push origin feat/x # then a pull request against main
git switch main && git pull --ff-only origin main
never by a push to `main`
`git push` the branch, then open a pull request against main
`main` changes only through a merged pull request: the branch is pushed, `main` is not
/usr/bin/git push origin feat/x
git push origin 'feat/x'
EOF
  printf 'git push origin feat/x\r\n' > "$t/line.md"
  readme_push_main "$t/line.md" >/dev/null && { echo "selftest FAIL: no push to main, but reported: git push origin feat/x + carriage return"; rc=1; }
  # block cases for check 7 (issue #18), straight at readme_push_main through push_block: the first argument is the
  # line number(s) that must be reported ('' = nothing), the rest are the lines of the fixture. F is a code fence.
  local F='```'
  # form 1 — a command wrapped with a backslash: 4 reported (at the line where the command starts), 4 left alone
  push_block 1 'git push origin \' '  main' || rc=1
  push_block 1 'git push \' '  -u origin \' '  HEAD:main' || rc=1
  push_block 2 'git fetch origin && \' '  git push origin main' || rc=1
  push_block 3 'git push -u origin \' '  feat/x' 'git push origin main' || rc=1
  push_block '' 'git push -u origin \' '  feat/x' || rc=1
  push_block '' 'git push -u origin feat/x \' '  && git switch main' || rc=1
  push_block '' 'git push -u \' '  origin \' '  main:feat/x' || rc=1
  push_block '' "$F" 'git switch main \' "$F" 'git push' || rc=1
  # form 2 — options between git and push: 4 reported, 4 left alone
  push_block 1 'git -C ../x push origin main' || rc=1
  push_block 1 'git -c a=b push origin HEAD:main' || rc=1
  push_block 1 'git --git-dir ../x/.git --work-tree=../x push origin main' || rc=1
  push_block 1 'Then run `git --no-pager push -u origin main`.' || rc=1
  push_block '' 'git -C ../x push -u origin feat/x' || rc=1
  push_block '' 'git -C ../x pull origin main' || rc=1
  push_block '' 'git -C main push origin feat/x' || rc=1
  push_block '' 'git -C push pull origin main' || rc=1
  # form 3 — --all / --mirror (and --branches, the newer name of --all): 5 reported, 6 left alone
  push_block 1 'git push --all' || rc=1
  push_block 1 'git push origin --mirror' || rc=1
  push_block 1 'git push --all origin' || rc=1
  push_block 1 'git push --branches origin' || rc=1
  push_block 1 'Then run `git push --all`.' || rc=1
  push_block '' 'git push --tags origin feat/x' || rc=1
  push_block '' 'git push --force-with-lease origin feat/x' || rc=1
  push_block '' 'git fetch --all' || rc=1
  push_block '' 'git fetch --all && git push -u origin feat/x' || rc=1
  push_block '' 'git push origin feat/all' || rc=1
  push_block '' 'git push origin feat/x # --all and --mirror are rejected' || rc=1
  # form 4 — a push without a ref while main is checked out, inside one code block: 12 reported, 14 left alone
  push_block 3 "$F" 'git switch main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout main' 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git switch main && git pull --ff-only origin main' 'git push' "$F" || rc=1
  push_block 2 "$F" 'git switch main && git push' "$F" || rc=1
  push_block 1 'git checkout main && git push origin' || rc=1
  push_block 2 "$F" '(git switch main && git push)' "$F" || rc=1
  push_block '3 4' "$F" 'git switch main' 'git push' 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git switch main' 'git push -u origin HEAD' "$F" || rc=1
  push_block 3 "$F" 'git switch main' 'git push --force-with-lease' "$F" || rc=1
  push_block 3 "$F" 'git switch main' 'git push -o ci.skip origin' "$F" || rc=1
  push_block 3 "$F" 'git checkout -B main origin/main' 'git push' "$F" || rc=1
  push_block 4 "$F" 'git switch main' 'git checkout -- README.md' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch -c feat/x --no-track origin/main' 'git push -u origin feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch main && git pull --ff-only origin main' './install.sh /tmp/a/.claude' './install.sh /tmp/b/.claude' "$F" || rc=1
  push_block '' "$F" 'git add README.md' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch -c feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git checkout main' 'git checkout -b feat/x' 'git push origin' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch --detach origin/main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' "$F" '' "$F" 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git push -u origin feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git push origin HEAD:feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git push -o ci.skip origin feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git push origin --tags' "$F" || rc=1
  push_block '' "$F" 'git switch maintenance' 'git push' "$F" || rc=1
  push_block '' 'After `git switch main` the install runs.' 'Then `git push` the branch.' || rc=1
  # block cases for check 7 (issue #30), three more forms. R is a carriage return, FR a code fence that ends in one.
  local R=$'\r' FR
  FR="$F$R"
  # form 5 — git called by its path (a command word that ends in /git): 5 reported, 7 left alone. A word that only
  # ends in the letters git (legit, my-git, .git) is still no command, and a path that ends in /git is one only when
  # the word after it (options aside) is push, switch or checkout.
  push_block 1 '/usr/bin/git push origin main' || rc=1
  push_block 1 './git push -u origin HEAD:main' || rc=1
  push_block 1 '(/usr/bin/git -C ../x push origin main)' || rc=1
  push_block 1 'Then run `/usr/local/bin/git push --all`.' || rc=1
  push_block 3 "$F" '/usr/bin/git switch main' '/usr/bin/git push' "$F" || rc=1
  push_block '' '/usr/bin/git push -u origin feat/x' || rc=1
  push_block '' '/usr/bin/git pull origin main' || rc=1
  push_block '' 'git clone https://example.org/git main' || rc=1
  push_block '' 'git -C ../git push origin feat/x' || rc=1
  push_block '' 'git push origin feat/git' || rc=1
  push_block '' 'legit push origin main' || rc=1
  push_block '' './my-git push origin main' || rc=1
  # form 6 — single quotes around the ref or around the whole command: 5 reported, 5 left alone
  push_block 1 "git push origin 'main'" || rc=1
  push_block 1 "git push origin 'HEAD:main'" || rc=1
  push_block 1 "sh -c 'git push origin main'" || rc=1
  push_block 1 "sh -c 'git switch main && git push'" || rc=1
  push_block 3 "$F" "git switch 'main'" 'git push' "$F" || rc=1
  push_block '' "git push origin 'feat/x'" || rc=1
  push_block '' "git push origin 'main:feat/x'" || rc=1
  push_block '' "git push origin 'maintenance'" || rc=1
  push_block '' "git commit -m 'main' && git push -u origin feat/x" || rc=1
  push_block '' "sh -c 'git switch feat/x && git push'" || rc=1
  # form 7 — lines that end in a carriage return (CRLF line endings): 6 reported, 5 left alone. The sixth reported
  # one (the ref is not the last word of the line) was seen before issue #30 too; it is here because the issue names
  # it as not measured.
  push_block 1 "git push origin main$R" || rc=1
  push_block 1 "git push -u origin HEAD:main$R" || rc=1
  push_block 1 "git push --all$R" || rc=1
  push_block 1 "git push origin \\$R" "  main$R" || rc=1
  push_block 3 "$FR" "git switch main$R" "git push$R" "$FR" || rc=1
  push_block 1 "git push origin main && echo done$R" || rc=1
  push_block '' "git push -u origin feat/x$R" || rc=1
  push_block '' "git push origin maintenance$R" || rc=1
  push_block '' "git push -u origin \\$R" "  feat/x$R" || rc=1
  push_block '' "$FR" "git switch main$R" "git switch feat/x$R" "git push$R" "$FR" || rc=1
  push_block '' "$FR" "git switch main$R" "$FR" "$R" "$FR" "git push$R" "$FR" || rc=1
  # block cases for check 7 (issue #33), one more form.
  # form 8 — the command word in quotes ("git", 'git', "/usr/bin/git"): 10 reported, 13 left alone. The quotes at the
  # end of the command word are dropped before it is tested; the rule for the word itself is the one of form 5 (git,
  # or a path that ends in /git - not legit, my-git, .git), and a quoted path or URL that ends in /git matters only
  # when the word after it (options aside) is push, switch or checkout.
  push_block 1 '"/usr/bin/git" push origin main' || rc=1
  push_block 1 '"git" push origin main' || rc=1
  push_block 1 "'git' push origin main" || rc=1
  push_block 1 "'/usr/bin/git' push -u origin HEAD:main" || rc=1
  push_block 1 '"git" -C ../x push origin main' || rc=1
  push_block 1 '("/usr/bin/git" push origin main)' || rc=1
  push_block 1 'Then run `"git" push --all`.' || rc=1
  push_block 1 '"/opt/my tools/git" push origin main' || rc=1
  push_block 1 '/usr/bin/"git" push origin main' || rc=1
  push_block 3 "$F" '"git" switch main' '"git" push' "$F" || rc=1
  push_block '' '"/usr/bin/git" push -u origin feat/x' || rc=1
  push_block '' '"git" push origin feat/x' || rc=1
  push_block '' "'git' pull origin main" || rc=1
  push_block '' '"legit" push origin main' || rc=1
  push_block '' '"my-git" push origin main' || rc=1
  push_block '' '"x/.git" push origin main' || rc=1
  push_block '' 'git clone "https://example.org/git" main' || rc=1
  push_block '' 'git -C "../git" push origin feat/x' || rc=1
  push_block '' 'echo "git" && git push -u origin feat/x' || rc=1
  push_block '' "$F" '"git" switch main' '"git" switch feat/x' '"git" push' "$F" || rc=1
  # the last three are not left alone because they are harmless: they are the forms the check cannot read (named
  # under "Still not seen" above readme_push_main). A variable cannot be resolved from the text, and the quote that
  # closes "$(...)" is dropped while the bracket in front of it stays, so the word is still no git.
  push_block '' '"$GIT" push origin main' || rc=1
  push_block '' '$(command -v git) push origin main' || rc=1
  push_block '' '"$(command -v git)" push origin main' || rc=1
  # block cases for check 7 (issue #32), one more form. T is a tab.
  # form 9 — a push without a ref while main is checked out, in an indented code block (four blanks or a tab in
  # front of the line, no fence): 12 reported, 14 left alone. Outside a fence the state lives from one indented line
  # to the next; an empty line between two indented lines belongs to the block and keeps it; the first line with
  # text that is not indented that far ends it. The state has to be set inside the indented lines: a switch to main
  # in a line that is not indented lives for that line only, as before.
  local T=$'\t'
  push_block 2 '    git switch main' '    git push' || rc=1
  push_block 4 'An indented block:' '' '    git switch main' '    git push' || rc=1
  push_block 2 "${T}git switch main" "${T}git push" || rc=1
  push_block 2 "  ${T}git switch main" "  ${T}git push origin" || rc=1
  push_block 3 '    git switch main' '' '    git push' || rc=1
  push_block 3 '    git switch main' '  ' '    git push' || rc=1
  push_block 3 '    git checkout main' '    git pull --ff-only origin main' '    git push origin' || rc=1
  push_block 2 '    git switch main' '    git push -u origin HEAD' || rc=1
  push_block 2 '        git switch main' '        git push' || rc=1
  push_block '2 3' '    git switch main' '    git push' "${T}git push origin" || rc=1
  push_block 3 '    git switch main && \' '      git pull --ff-only origin main' '    git push' || rc=1
  push_block 3 "    git switch main$R" "$R" "    git push$R" || rc=1
  push_block '' '    git switch main' 'Then, on the work branch:' '    git push' || rc=1
  push_block '' '    git switch main' '' 'Then, on the work branch:' '' '    git push' || rc=1
  push_block '' '    git switch main' '    git pull --ff-only origin main' || rc=1
  push_block '' '    git switch main' '    git push -u origin feat/x' || rc=1
  push_block '' '    git switch main' '    git push origin --tags' || rc=1
  push_block '' '    git switch main' '    git switch feat/x' '    git push' || rc=1
  push_block '' '    git switch main' '    git switch -c feat/x' '    git push' || rc=1
  push_block '' '    git add README.md' '    git push' || rc=1
  push_block '' '    git switch main' 'git push' || rc=1
  push_block '' 'Run `git switch main` first.' '' '    git push' || rc=1
  push_block '' 'git switch main' '    git push' || rc=1
  push_block '' '   git switch main' '   git push' || rc=1
  push_block '' '    git switch main' "$F" 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' "$F" '    git push' || rc=1
  # block cases for check 7 (issue #41), one more form.
  # form 10 — the subcommand in quotes (git "push", git 'switch', git "checkout"): 13 reported, 15 left alone. A word
  # that is push, switch or checkout between one pair of quotes is that subcommand and the words after it are its
  # arguments; closing punctuation behind the pair ends the command at the word, as it does behind the bare word.
  push_block 1 'git "push" origin main' || rc=1
  push_block 1 "git 'push' origin main" || rc=1
  push_block 1 'git "push" origin "main"' || rc=1
  push_block 1 'git -C ../x "push" -u origin HEAD:main' || rc=1
  push_block 1 "\"git\" 'push' --all" || rc=1
  push_block 1 'Then run `git "push" origin main`.' || rc=1
  push_block 1 "sh -c \"git 'push' origin main\"" || rc=1
  push_block 3 "$F" 'git "switch" main' 'git push' "$F" || rc=1
  push_block 3 "$F" "git 'checkout' main" 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git switch main' 'git "push"' "$F" || rc=1
  push_block 2 '    git "switch" main' "    git 'push'" || rc=1
  push_block 1 "sh -c 'git switch main && git \"push\"'" || rc=1
  # the thirteenth was reported before issue #41 too. It is here because the new rule must not change it: the quote
  # behind push closes the whole command, so the words after it are arguments of sh, not a remote and a ref - the
  # push carries no ref and main is checked out.
  push_block 3 "$F" 'git switch main' "sh -c 'git push' origin feat/x" "$F" || rc=1
  push_block '' 'git "push" origin feature' || rc=1
  push_block '' "git 'push' -u origin 'feat/x'" || rc=1
  push_block '' 'git "push" origin main:feat/x' || rc=1
  push_block '' 'git "status"' || rc=1
  push_block '' 'git "pull" origin main' || rc=1
  # the quote closes the whole command (no quote in front of push): the command ends at the word, as before
  push_block '' "sh -c 'git push' origin main" || rc=1
  # one quoted word for git, and a quote that is not closed by its own kind: neither is a pair around push
  push_block '' "git 'push origin main'" || rc=1
  push_block '' "git \"push' origin main" || rc=1
  # a quoted switch to another branch clears the state. Before issue #41 it was not read, the state stayed on main
  # and the push in the first of these four was reported at line 4 - a report for a push of feat/x.
  push_block '' "$F" 'git switch main' 'git "switch" feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git "switch" main' "git 'switch' -c feat/x" 'git push' "$F" || rc=1
  push_block '' "$F" 'git "checkout" feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git "switch" main' 'git push -u origin feat/x' "$F" || rc=1
  push_block '' "sh -c 'git switch feat/x && git \"push\"'" || rc=1
  # the last two are not left alone because they are harmless: they are the second form of issue #41, quotes or a
  # backslash inside the command word, which was decided not to be built (named under "Still not seen" above
  # readme_push_main with the reason). The shell runs both as git push origin main.
  push_block '' 'gi"t" push origin main' || rc=1
  push_block '' 'g\it push origin main' || rc=1
  # block cases for check 7 (issue #49), the fence line. It belongs to form 9 (issue #32) and uses its T.
  # form 11 — a line of three backticks or tildes is a fence line only with at most three blanks and no tab in front
  # (the CommonMark rule); indented further it is one more line of an indented code block, or of the fence it stands
  # in: 9 reported, 10 left alone.
  # the form of the issue: switch to main, the indented line, push without a ref - backticks, tildes, a tab, a tab
  # after two blanks, and the six lines of the measurement in the issue (text, empty line, block)
  push_block 3 '    git switch main' "    $F" '    git push' || rc=1
  push_block 3 '    git switch main' '    ~~~' '    git push' || rc=1
  push_block 3 "${T}git switch main" "${T}$F" "${T}git push" || rc=1
  push_block 3 "  ${T}git switch main" "  ${T}~~~" "  ${T}git push origin" || rc=1
  push_block 5 'An indented block:' '' '    git switch main' "    $F" '    git push' || rc=1
  # the list-item form: fence lines and commands all indented by four blanks. The fence is no longer seen as one, but
  # all its lines are lines of one indented block and the state lives across them - reported before issue #49 as well
  push_block 5 '1. Update main:' '' "    ${F}bash" '    git switch main' '    git push' "    $F" || rc=1
  # inside a real fence the indented line is content and does not close it: the state lives on to the push
  push_block 4 "$F" 'git switch main' "    $F" 'git push' "$F" || rc=1
  # the accepted limit, measured: two fenced blocks in one list item, indented by four blanks, are one indented block
  # for this check (an empty line belongs to it), so the switch in the first reaches the push in the second. Before
  # issue #49 each of the four lines ended the state. It can only report more.
  push_block 8 '- step:' '' "    $F" '    git switch main' "    $F" '' "    $F" '    git push' "    $F" || rc=1
  # the second place of the rule, the join of a wrapped command: a line that ends in a backslash is joined with an
  # indented line of three tildes too, it is no fence. Built for that place - ~~~ stands where the remote is.
  push_block 1 '    git push \' '    ~~~ origin main' || rc=1
  # left alone. With three blanks in front the line is a real fence: it ends the state, as before
  push_block '' '    git switch main' "   $F" '    git push' || rc=1
  push_block '' '    git switch main' '   ~~~' '    git push' || rc=1
  push_block '' "   $F" '   git switch main' "   $F" '    git push' || rc=1
  push_block '' "$F" 'git switch main' "   $F" 'git push' || rc=1
  push_block '' '    git push \' '   ~~~ origin main' || rc=1
  # an indented line of three backticks opens no fence: before issue #49 it opened one that nothing closed, the state
  # lived to the end of the file and the push in line 4 was reported
  push_block '' "    $F" 'git switch main' 'Some prose.' 'git push' || rc=1
  # the indented line changes nothing about what ends or clears the state of an indented block
  push_block '' '    git switch main' "    $F" 'Then, on the work branch:' '    git push' || rc=1
  push_block '' '    git switch main' "    $F" '    git switch feat/x' '    git push' || rc=1
  push_block '' '    git add README.md' "    $F" '    git push' || rc=1
  push_block '' '- a:' '' "    $F" '    git switch main' "    $F" '' '- b:' '' "    $F" '    git push' "    $F" || rc=1
  # block cases for check 7 (issue #66), what closes a fenced block. F4 is a fence of four backticks.
  # form 12 — a fenced block is closed only by a line of the character that opened it, with a run at least as long
  # as the opening one and nothing but blanks or tabs behind it (the CommonMark rule, FENCE_AWK). Every other line
  # that starts like a fence line is content there and does not end the state: 12 reported, 11 left alone.
  local F4='````'
  # the two forms of the issue: a line of tildes inside a backtick block, and a line of three backticks inside a
  # block of four (how a README shows a fenced block)
  push_block 4 "$F" 'git switch main' '~~~' 'git push' "$F" || rc=1
  push_block 4 "$F4" 'git switch main' "$F" 'git push' "$F4" || rc=1
  # what the issue names as not measured: the other direction, and text behind the run (in CommonMark it does not
  # close); then a shorter run of tildes, and the inner line with three blanks in front
  push_block 4 '~~~' 'git switch main' "$F" 'git push' '~~~' || rc=1
  push_block 4 "$F" 'git switch main' "${F}bash" 'git push' "$F" || rc=1
  push_block 4 '~~~~' 'git switch main' '~~~' 'git push origin' '~~~~' || rc=1
  push_block 4 "$F" 'git switch main' '   ~~~' 'git push' "$F" || rc=1
  # a fenced block shown inside a longer one: the inner opening line carries an info string and ended the outer
  # block before, so the two commands were two lines outside a fence
  push_block 4 "${F4}markdown" "${F}bash" 'git switch main' 'git push' "$F" "$F4" || rc=1
  # a block that nothing closes runs to the end of the file, and the state with it (it can only report more)
  push_block 5 "$F4" 'git switch main' "$F" 'Some prose.' 'git push' || rc=1
  # after a long block that is closed by its own kind, the next line of three backticks opens a block. Before, the
  # four fence lines were read as two blocks and the commands stood outside
  push_block 7 "$F4" 'git switch feat/x' "$F" "$F4" "$F" 'git switch main' 'git push' "$F" || rc=1
  # lines that end in a carriage return
  push_block 4 "$F4$R" "git switch main$R" "$FR" "git push$R" "$F4$R" || rc=1
  # the second place of the rule, the join of a wrapped command: inside a backtick block a line that ends in a
  # backslash is joined with a line that starts with tildes, it closes nothing. Built for that place - ~~~ stands
  # where the remote is.
  push_block 2 "$F" 'git push \' '~~~ origin main' "$F" || rc=1
  # the twelfth was reported before issue #66 too: outside a block a line of tildes opens one, as before
  push_block 4 'text' '~~~' 'git switch main' 'git push' '~~~' || rc=1
  # left alone. What closes a block still ends the state: the same run, a longer one, blanks or a tab behind it
  push_block '' "$F4" 'git switch main' "$F4" 'git push' || rc=1
  push_block '' "$F" 'git switch main' "$F4" 'git push' || rc=1
  push_block '' '~~~' 'git switch main' '~~~~~' 'git push' || rc=1
  push_block '' "$F" 'git switch main' "$F  " 'git push' || rc=1
  push_block '' "$F" 'git switch main' "$F$T" 'git push' || rc=1
  # the inner line carries no state out of its block, and changes nothing about what clears the state inside it
  push_block '' "$F4" 'git switch main' "$F" "$F4" 'git push' || rc=1
  push_block '' "$F" 'git switch main' '~~~' 'git switch feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git add README.md' '~~~' 'git push' "$F" || rc=1
  push_block '' "$F4" 'git switch main' "$F" 'git push -u origin feat/x' "$F4" || rc=1
  # a wrapped command is still not joined with the line that closes its block
  push_block '' "$F" 'git push \' "$F" 'origin main' || rc=1
  # no longer reported: before issue #66 the line of three backticks ended the block of four and the closing line of
  # four opened one that nothing closed, so the state lived across the prose to the push in line 7. The three lines
  # behind the block are lines outside a fence, where the state lives for one line.
  push_block '' "$F4" 'text' "$F" "$F4" 'git switch main' 'Some prose.' 'git push' || rc=1
  # block cases for check 7 (issue #69), the opening line. It belongs to form 12 (issue #66) and uses its F4.
  # form 13 — a line that starts with a run of backticks and carries a backtick somewhere behind the run opens no
  # fenced block (the CommonMark rule for the info string of a backtick fence, fence_run in FENCE_AWK): it is a line
  # of a paragraph that starts with inline code. 6 reported, 11 left alone.
  # left alone. The five lines of the issue: a heading, an empty line, the sentence that starts with inline code in
  # three backticks, prose, a push. The sentence opened a block that nothing closed, so the state lived across the
  # prose to the push in line 5
  push_block '' '# Update' '' "${F}git switch main${F} is how the update starts." 'Some prose.' 'git push' || rc=1
  # the push straight behind the sentence: outside a block the state lives for one line
  push_block '' "${F}git switch main${F} is how the update starts." 'git push' || rc=1
  # what the issue names as not measured: a run of four backticks with a backtick behind it; then three blanks in
  # front, a backtick in the middle of what would be the info string, one at its very end, and carriage returns
  push_block '' "${F4}git switch main${F4} is how." 'Some prose.' 'git push' || rc=1
  push_block '' "   ${F}git switch main${F} is how." 'Some prose.' 'git push' || rc=1
  push_block '' "${F}bash \`-x\`" 'git switch main' 'Some prose.' 'git push' || rc=1
  push_block '' "${F}bash\`" 'git switch main' 'Some prose.' 'git push' || rc=1
  push_block '' "${F}git switch main${F} is how.$R" "Some prose.$R" "git push$R" || rc=1
  # the blocks behind such a sentence were read inverted: the real opening line closed, the real closing line opened
  # a block that nothing closed, and the state lived from the switch in line 5 across the prose to the push in line 7
  push_block '' "${F}make${F} builds it." "$F" 'git add .' "$F" 'git switch main' 'Some prose.' 'git push' || rc=1
  # two such sentences are two lines of prose, not the two ends of a block
  push_block '' "${F}a${F} one" 'git switch main' "${F}b${F} two" 'git push' || rc=1
  # inside a block such a line was content before and still is; the block is closed by its own kind as before
  push_block '' "$F" 'git switch main' "${F}x${F} y" "$F" 'git push' || rc=1
  # an opening line with an info string that carries no backtick still opens a block, and a wrapped command is still
  # not joined with it
  push_block '' 'git switch main && \' "${F}bash" 'git push' "$F" || rc=1
  # reported. The other side of the inverted blocks, not named in the issue: the real block behind such a sentence
  # was read as the lines between two blocks, so the switch in line 3 did not reach the push in line 4 - a report
  # that was missed, not one too many
  push_block 4 "${F}make${F} builds it. Then:" "$F" 'git switch main' 'git push' "$F" || rc=1
  # the second place of the rule, the join of a wrapped command: a line that ends in a backslash is joined with such
  # a sentence, it is no fence line. Built for that place - before, the sentence opened a block and cleared the state.
  push_block 2 'git switch main && \' "${F}x${F} ; git push" || rc=1
  # reported before issue #69 too. The rule is one for backticks: a line of tildes may carry a backtick behind its
  # run and still opens a block (in CommonMark the info string of a tilde fence may hold any character)
  push_block 4 '~~~ a`b' 'git switch main' 'Some prose.' 'git push' || rc=1
  # an info string without a backtick still opens a block, here one that nothing closes
  push_block 4 "${F}bash" 'git switch main' 'Some prose.' 'git push' || rc=1
  # inside a block such a line is content and leaves the state as it is
  push_block 4 "$F" 'git switch main' "${F}x${F} y" 'git push' "$F" || rc=1
  # the command inside the inline code is read as before: a push to main in such a sentence is a report at its line
  push_block 1 "${F}git push origin main${F} is what this check reports." || rc=1
  # block cases for check 7 (issue #24), two more ways to get main checked out. What git does with each command was
  # measured with scripts/branch-after-probe.sh (git 2.43.0, 2026-10-07); its selftest holds the same forms.
  # form 14 — a remote branch <remote>/main behind --track, -t, --track=<mode> or --no-track: git derives the name
  # of the new local branch from the part behind the first slash, so main is checked out. 12 reported, 13 left alone.
  # reported: the three commands of the issue, the short option at checkout too, the long option with a mode,
  # another remote, the long name of the remote branch, and --no-track (the probe: it derives main as well)
  push_block 3 "$F" 'git switch --track origin/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout --track origin/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git switch -t origin/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout -t origin/main' 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git switch --track=direct origin/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git switch --track upstream/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git switch --track refs/remotes/origin/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git switch --no-track origin/main' 'git push -u origin HEAD' "$F" || rc=1
  # in one line, in an indented block, and with the subcommand in quotes (form 8)
  push_block 1 'git switch --track origin/main && git push' || rc=1
  push_block 2 '    git checkout --track origin/main' '    git push' || rc=1
  push_block 3 "$F" 'git "switch" --track origin/main' 'git push' "$F" || rc=1
  # a new-branch option behind the start point names the branch: here it is main
  push_block 3 "$F" 'git switch --track origin/main -c main' 'git push' "$F" || rc=1
  # left alone: a new-branch option names another branch, in front of the start point or behind it
  push_block '' "$F" 'git switch -c feature --track origin/main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch --track origin/main -c feature' 'git push' "$F" || rc=1
  push_block '' "$F" 'git checkout -b feat/y --track origin/main' 'git push' "$F" || rc=1
  # no longer reported: the start point main with a new branch of another name behind it (the probe: feat/x is
  # checked out). Before, the first word main alone decided.
  push_block '' "$F" 'git switch main -c feat/x' 'git push' "$F" || rc=1
  # the remote branch is not main: another name, main as the last part of a longer name, a name that starts with main
  push_block '' "$F" 'git switch --track origin/feature' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch --track origin/topic/main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch --track origin/maintenance' 'git push' "$F" || rc=1
  # no option that derives a name: git switch rejects the command, git checkout detaches (as before)
  push_block '' "$F" 'git switch origin/main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git checkout origin/main' 'git push' "$F" || rc=1
  # the state is cleared and scoped as for git switch main: another branch behind it, a push of another branch, the
  # next code block (named under "Still not seen"), and a sentence that names the command
  push_block '' "$F" 'git switch --track origin/main' 'git switch feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch --track origin/main' 'git push -u origin feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch --track origin/main' "$F" '' "$F" 'git push' "$F" || rc=1
  push_block '' 'After `git switch --track origin/main` the install runs.' 'Then `git push` the branch.' || rc=1
  # form 15 — git branch -m / -M / --move with the new name main: the current branch is called main from then on.
  # 12 reported, 14 left alone.
  # reported: the two commands of the issue, the long option, the form with the old name in front, a push of HEAD
  push_block 3 "$F" 'git branch -M main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git branch -m main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git branch --move main' 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git branch -m master main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git branch -M main' 'git push -u origin HEAD' "$F" || rc=1
  # in one line, in an indented block, with the subcommand in quotes, with options between git and branch, and with
  # a command between the rename and the push
  push_block 1 'git branch -M main && git push' || rc=1
  push_block 2 '    git branch -M main' '    git push' || rc=1
  push_block 3 "$F" 'git "branch" -M main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git -C ../x branch -M main' 'git -C ../x push' "$F" || rc=1
  push_block 4 "$F" 'git branch -M main' 'git remote add origin https://example.org/x.git' 'git push' "$F" || rc=1
  # reported before too, and still: main is checked out and git branch does not change that - the rename of another
  # branch, a new branch that is only created
  push_block 4 "$F" 'git switch main' 'git branch -m feat/a feat/b' 'git push' "$F" || rc=1
  push_block 4 "$F" 'git switch main' 'git branch feat/x' 'git push' "$F" || rc=1
  # left alone: the new name is not main, or the command renames nothing (create, delete, copy, list, set upstream -
  # a push configured elsewhere is named under "Still not seen")
  push_block '' "$F" 'git branch -M trunk' 'git push' "$F" || rc=1
  push_block '' "$F" 'git branch -M maintenance' 'git push' "$F" || rc=1
  push_block '' "$F" 'git branch -m feat/a main-menu' 'git push' "$F" || rc=1
  push_block '' "$F" 'git branch main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git branch -d main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git branch -c main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git branch --list main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git branch -u origin/main' 'git push' "$F" || rc=1
  # no longer reported: main was checked out and is renamed away (the probe: trunk is checked out, the push without a
  # ref is refused). Before, git branch was not read and the state of the switch lived on.
  push_block '' "$F" 'git switch main' 'git branch -m trunk' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git branch -m main trunk' 'git push' "$F" || rc=1
  # the state is cleared and scoped as for git switch main
  push_block '' "$F" 'git branch -M main' 'git switch feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git branch -M main' 'git push -u origin feat/x' "$F" || rc=1
  push_block '' "$F" 'git branch -M main' "$F" '' "$F" 'git push' "$F" || rc=1
  push_block '' 'After `git branch -M main` the remote is added.' 'Then `git push` the branch.' || rc=1
  # block cases for check 7 (issue #75), how the options of a switch or checkout are read - three ways to write one
  # that the reader of issue #24 took for something else. What git does with each command was measured with
  # scripts/branch-after-probe.sh (git 2.43.0, 2026-10-07); its selftest holds the same forms.
  # form 16 — an option that takes a value as its own word (--conflict <style>, and at checkout
  # --pathspec-from-file <file>): the word behind it is the value, not the branch. 8 reported, 4 left alone.
  # reported: the command of the issue, at checkout too, the three styles, in one line, with a track option behind
  # it, and the file option of checkout (the probe: with a file that names no path git switches the branch)
  push_block 3 "$F" 'git switch --conflict diff3 main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout --conflict merge main' 'git push origin' "$F" || rc=1
  push_block 1 'git switch --conflict zdiff3 main && git push' || rc=1
  push_block 3 "$F" 'git switch --conflict diff3 --track origin/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout --pathspec-from-file list.txt main' 'git push' "$F" || rc=1
  push_block 4 "$F" 'git switch feat/x' 'git switch --conflict diff3 main' 'git push -u origin HEAD' "$F" || rc=1
  # reported before too, and still: the value glued to the option with "=", and an option whose value is optional -
  # git takes the word behind --recurse-submodules for the branch (the probe: main is checked out)
  push_block 3 "$F" 'git switch --conflict=diff3 main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git switch --recurse-submodules main' 'git push' "$F" || rc=1
  # left alone: the branch behind the value is another one; and the value itself is called main (git rejects the
  # style and stays where it was - before, the word main behind the option was read as the branch)
  push_block '' "$F" 'git switch --conflict diff3 feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch --conflict diff3 feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch --conflict main feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git checkout --pathspec-from-file main feat/x' 'git push' "$F" || rc=1
  # form 17 — short options written as one word (-ft, -qt, -fd): every letter is an option of its own, and a
  # letter that takes a value takes the rest of the word. 6 reported, 5 left alone.
  # reported: the command of the issue, at checkout, another letter in front, the mode glued to -t, in an indented
  # block, and a new-branch letter at the end of the word with the name main behind it (reported before too)
  push_block 3 "$F" 'git switch -ft origin/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout -ft origin/main' 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git checkout -qt upstream/main' 'git push -u origin HEAD' "$F" || rc=1
  push_block 3 "$F" 'git switch -tdirect origin/main' 'git push' "$F" || rc=1
  push_block 2 '    git switch -ft origin/main' '    git push' || rc=1
  push_block 3 "$F" 'git switch -fc main' 'git push' "$F" || rc=1
  # left alone: the remote branch is not main; the word carries the letter of --detach (before, -fd was no detach
  # option, and the word main behind it set the state); and a new-branch letter with another name behind it
  push_block '' "$F" 'git switch -ft origin/feature' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch -ft origin/topic/main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch -fd main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch -fd origin/main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch -fc feat/x' 'git push' "$F" || rc=1
  # form 18 — the name glued to a new-branch option: -cmain, -Cmain, -bmain, -Bmain, behind other letters too
  # (-fcmain), and the long options with "=" (--create=main, --force-create=main, --orphan=main).
  # 11 reported, 9 left alone.
  # reported: the two commands of the issue, the forced letters, a start point behind the name, another letter in
  # front, the three long options, the name in quotes, and the subcommand in quotes (form 8)
  push_block 3 "$F" 'git switch -cmain' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout -bmain' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git switch -Cmain origin/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout -Bmain' 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git switch -fcmain' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git switch --create=main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git switch --force-create=main origin/main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout --orphan=main' 'git push -u origin HEAD' "$F" || rc=1
  push_block 3 "$F" 'git switch -c"main"' 'git push' "$F" || rc=1
  push_block 1 'git switch -cmain && git push' || rc=1
  push_block 3 "$F" 'git "switch" -cmain' 'git push' "$F" || rc=1
  # left alone: the glued name is another one - before, the word was skipped as an option, so the state of the
  # switch to main in front of it lived on, and a start point main behind it set the state
  push_block '' "$F" 'git switch main' 'git switch -cfeat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git checkout main' 'git checkout -bfeat/x' 'git push origin' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch --create=feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch -cfeat/x main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch -cmaintenance' 'git push' "$F" || rc=1
  # the state is cleared and scoped as for git switch main
  push_block '' "$F" 'git switch -cmain' 'git switch feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch -cmain' 'git push -u origin feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch -cmain' "$F" '' "$F" 'git push' "$F" || rc=1
  push_block '' 'After `git switch -cmain` the install runs.' 'Then `git push` the branch.' || rc=1
  # pushwrapped / pushonmain / pushflow: the same through run_checks, like pushmain above (block at line 20). The
  # wrapped command is named at the line where it starts (21), the push without a ref at its own line (22); the
  # step-3 block of the real README (switch to main, pull, install) stays accepted.
  cp -r "$t/listed" "$t/pushwrapped"
  printf '\n```bash\ngit push origin \\\n  main\n```\n' >> "$t/pushwrapped/README.md"
  out="$(run_checks "$t/pushwrapped")"
  case "$out" in
    *"FAIL: README.md:21: git push to main"*) ;;
    *) echo "selftest FAIL: README with a wrapped 'git push origin main' accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushonmain"
  printf '\n```bash\ngit switch main\ngit push\n```\n' >> "$t/pushonmain/README.md"
  out="$(run_checks "$t/pushonmain")"
  case "$out" in
    *"FAIL: README.md:22: git push to main"*) ;;
    *) echo "selftest FAIL: README with 'git switch main' + 'git push' in one block accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushflow"
  printf '\n```bash\ngit switch main && git pull --ff-only origin main\n./install.sh /tmp/x/.claude\n```\n' >> "$t/pushflow/README.md"
  run_checks "$t/pushflow" >/dev/null || { echo "selftest FAIL: README with 'git switch main && git pull' + install rejected"; rc=1; }
  # pushcrlf / pushcrlfbranch (issue #30): the listed README with CRLF line endings on every line, plus a push block
  # (block at line 20, command at 21). Before issue #30 the last word of the command was "main" + carriage return and
  # the whole file passed check 7. The FAIL line names line 21 and carries no carriage return; the same file with a
  # push of a branch stays accepted.
  cp -r "$t/listed" "$t/pushcrlf"
  {
    while IFS= read -r line; do printf '%s\r\n' "$line"; done < "$t/listed/README.md"
    printf '\r\n```bash\r\ngit push origin main\r\n```\r\n'
  } > "$t/pushcrlf/README.md"
  out="$(run_checks "$t/pushcrlf")"
  case "$out" in
    *"FAIL: README.md:21: git push to main"*"$R"*) echo "selftest FAIL: the FAIL line for a CRLF README carries a carriage return"; rc=1 ;;
    *"FAIL: README.md:21: git push to main"*) ;;
    *) echo "selftest FAIL: README with CRLF line endings and 'git push origin main' accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushcrlfbranch"
  {
    while IFS= read -r line; do printf '%s\r\n' "$line"; done < "$t/listed/README.md"
    printf '\r\n```bash\r\ngit push -u origin feat/x\r\n```\r\n'
  } > "$t/pushcrlfbranch/README.md"
  out="$(run_checks "$t/pushcrlfbranch")" || {
    echo "selftest FAIL: README with CRLF line endings and 'git push -u origin feat/x' rejected:"
    printf '%s\n' "$out"
    rc=1
  }
  # pushindent / pushindentflow (issue #32): the listed README plus an indented code block (no fence). The appended
  # text is an empty line (19), a sentence (20), an empty line (21) and the two command lines (22, 23) - the fixture
  # of the issue. The push without a ref is named at its own line (23); the same block with a switch to main, a pull
  # and the install (step 3 of the real README, written as an indented block) stays accepted.
  cp -r "$t/listed" "$t/pushindent"
  printf '\nAn indented block:\n\n    git switch main\n    git push\n' >> "$t/pushindent/README.md"
  out="$(run_checks "$t/pushindent")"
  case "$out" in
    *"FAIL: README.md:23: git push to main"*) ;;
    *) echo "selftest FAIL: README with 'git switch main' + 'git push' in an indented code block accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushindentflow"
  printf '\nAn indented block:\n\n    git switch main && git pull --ff-only origin main\n    ./install.sh /tmp/x/.claude\n' >> "$t/pushindentflow/README.md"
  out="$(run_checks "$t/pushindentflow")" || {
    echo "selftest FAIL: README with 'git switch main && git pull' + install in an indented code block rejected:"
    printf '%s\n' "$out"
    rc=1
  }
  # cwdagent / cwdagentbad (check 3, issue #21): agent-file-check.py looks up the paths an agent file names in its
  # working directory, so the gate has to start it in the root it checks - otherwise the result depends on where the
  # gate was started. Both fixtures are the good one plus a .claude/agents/r.md that names
  # `docs/gate-cwd-case/marker.md`.
  #   cwdagent:    the path exists below the fixture; run_checks is started in an empty directory -> accepted
  #                (check 3 in the caller's directory: "Pfad fehlt", gate red on a good tree - the case of the issue)
  #   cwdagentbad: the path is missing below the fixture; run_checks is started in a directory that has it
  #                -> rejected by check 3 (check 3 in the caller's directory: gate green on a broken tree)
  # The caller's working directory is the same after run_checks as before.
  # Without the store program check 3 is skipped with a note, and so are these cases.
  if [ -f "$AGENT_CHECKER" ]; then
    cp -r "$t/good" "$t/cwdagent"
    mkdir -p "$t/cwdagent/.claude/agents" "$t/cwdagent/docs/gate-cwd-case" "$t/elsewhere" "$t/decoy/docs/gate-cwd-case"
    printf -- '---\nname: r\ndescription: selftest role file for check 3\nmodel: sonnet\ntools: Read\n---\n# Role r\n\nRead first: `docs/gate-cwd-case/marker.md`.\n' > "$t/cwdagent/.claude/agents/r.md"
    printf 'marker\n' > "$t/cwdagent/docs/gate-cwd-case/marker.md"
    out="$(cd "$t/elsewhere" && run_checks "$t/cwdagent" 2>&1)" || {
      echo "selftest FAIL: agent file whose named path exists below the checked root rejected when started in another directory:"
      printf '%s\n' "$out"
      rc=1
    }
    ( cd "$t/elsewhere" && here="$(pwd)" && { run_checks "$t/cwdagent" >/dev/null 2>&1; [ "$(pwd)" = "$here" ]; } ) || {
      echo "selftest FAIL: run_checks left its caller in another working directory"; rc=1; }
    cp -r "$t/good" "$t/cwdagentbad"
    mkdir -p "$t/cwdagentbad/.claude/agents"
    cp "$t/cwdagent/.claude/agents/r.md" "$t/cwdagentbad/.claude/agents/r.md"
    printf 'marker\n' > "$t/decoy/docs/gate-cwd-case/marker.md"
    out="$(cd "$t/decoy" && run_checks "$t/cwdagentbad" 2>&1)" && {
      echo "selftest FAIL: agent file whose named path is missing below the checked root accepted when started in a directory that has it"; rc=1; }
    printf '%s\n' "$out" | grep -q 'FAIL: agent-file-check on .claude/agents' || {
      echo "selftest FAIL: cwdagentbad not rejected by check 3"; rc=1; }
  else
    echo "selftest note: the check 3 cases cwdagent and cwdagentbad skipped (no store program agent-file-check.py)"
  fi
  # tool file cases (check 7, issue #25): the listed fixture (checks 1 to 6 green, README without a push) plus a push
  # instruction in a file that install.sh copies into a project - there it is repeated in every session. 7 rejected
  # (one per kind of installed file, and two that are reached through a symlink), each by exactly one FAIL line
  # that names the file, the line and the command; 2 accepted. The fixture files: agents/a.md and skills/x/SKILL.md have 5 lines, commands/c.md has 1; an appended
  # block starts with a blank line.
  #   toolagent:     agents/a.md + a code block                      -> the command is line 8
  #   toolcommand:   commands/c.md + a sentence with inline code     -> line 3
  #   toolskill:     skills/x/SKILL.md + a block that switches to main and pushes without a ref -> the push, line 9
  #   toolskillfile: a new file skills/x/references/flow.md          -> line 3
  #   toolhidden:    a new hidden file skills/x/.notes.md            -> line 1
  #   toolevals:     the same command in skills/x/evals/e.md, which install.sh does not install -> accepted
  #   toolbranch:    agents/a.md + a push of a branch, main in prose -> accepted
  local why25='git push to main in a file install.sh installs (issue #25: it is repeated in every session of the projects it is installed into)'
  cp -r "$t/listed" "$t/toolagent"
  printf '\n```bash\ngit push origin main\n```\n' >> "$t/toolagent/agents/a.md"
  tool_file_case "agent file with 'git push origin main'" "$t/toolagent" "FAIL: agents/a.md:8: $why25: git push origin main" || rc=1
  cp -r "$t/listed" "$t/toolcommand"
  printf '\nThen run `git push origin HEAD:main`.\n' >> "$t/toolcommand/commands/c.md"
  tool_file_case "command file with 'git push origin HEAD:main' as inline code" "$t/toolcommand" "FAIL: commands/c.md:3: $why25: Then run \`git push origin HEAD:main\`." || rc=1
  cp -r "$t/listed" "$t/toolskill"
  printf '\n```bash\ngit switch main\ngit push\n```\n' >> "$t/toolskill/skills/x/SKILL.md"
  tool_file_case "SKILL.md with 'git switch main' + 'git push' in one block" "$t/toolskill" "FAIL: skills/x/SKILL.md:9: $why25: git push" || rc=1
  cp -r "$t/listed" "$t/toolskillfile"
  mkdir -p "$t/toolskillfile/skills/x/references"
  printf '# flow\n\ngit push --all\n' > "$t/toolskillfile/skills/x/references/flow.md"
  tool_file_case "file in a folder of a skill with 'git push --all'" "$t/toolskillfile" "FAIL: skills/x/references/flow.md:3: $why25: git push --all" || rc=1
  cp -r "$t/listed" "$t/toolhidden"
  printf 'git push -u origin feat/x:main\n' > "$t/toolhidden/skills/x/.notes.md"
  tool_file_case "hidden file of a skill with 'git push -u origin feat/x:main'" "$t/toolhidden" "FAIL: skills/x/.notes.md:1: $why25: git push -u origin feat/x:main" || rc=1
  #   toolagentlink: agents/a.md is a symlink to shared/a.md, a file outside agents/ that carries the command.
  #                  install.sh copies agents and commands with a plain cp, which copies what a link points to, so
  #                  the content reaches the project -> rejected, named by the path of the link, line 8
  #   toolskilllink: skills/x/more.md is a symlink (absolute target) to a file outside the skill that carries the
  #                  command. install.sh copies the entries of a skill with cp -r, which copies the link itself; on
  #                  the machine of the install the link still leads to that content -> rejected, line 1
  cp -r "$t/listed" "$t/toolagentlink"
  mkdir -p "$t/toolagentlink/shared"
  mv "$t/toolagentlink/agents/a.md" "$t/toolagentlink/shared/a.md"
  printf '\n```bash\ngit push origin main\n```\n' >> "$t/toolagentlink/shared/a.md"
  ln -s ../shared/a.md "$t/toolagentlink/agents/a.md"
  tool_file_case "agent file that is a symlink to a file with 'git push origin main'" "$t/toolagentlink" "FAIL: agents/a.md:8: $why25: git push origin main" || rc=1
  cp -r "$t/listed" "$t/toolskilllink"
  mkdir -p "$t/toolskilllink/shared"
  printf 'git push origin main\n' > "$t/toolskilllink/shared/more.md"
  ln -s "$t/toolskilllink/shared/more.md" "$t/toolskilllink/skills/x/more.md"
  tool_file_case "symlink inside a skill to a file with 'git push origin main'" "$t/toolskilllink" "FAIL: skills/x/more.md:1: $why25: git push origin main" || rc=1
  cp -r "$t/listed" "$t/toolevals"
  mkdir -p "$t/toolevals/skills/x/evals"
  printf 'git push origin main\n' > "$t/toolevals/skills/x/evals/e.md"
  out="$(run_checks "$t/toolevals" 2>&1)" || {
    echo "selftest FAIL: 'git push origin main' in a skill's evals/ (not installed) rejected:"
    printf '%s\n' "$out"
    rc=1
  }
  cp -r "$t/listed" "$t/toolbranch"
  printf '\nThe change reaches `main` through a pull request, never by a push to `main`:\n\n```bash\ngit push -u origin feat/x\n```\n' >> "$t/toolbranch/agents/a.md"
  out="$(run_checks "$t/toolbranch" 2>&1)" || {
    echo "selftest FAIL: agent file with 'git push -u origin feat/x' rejected:"
    printf '%s\n' "$out"
    rc=1
  }
  # directory link cases (check 7, issue #51): the listed fixture plus a symlink to a directory inside skills/x.
  # install.sh copies an entry of a skill with cp -r, which copies such a link as a link, and tool_files does not go
  # behind it - so until issue #51 a push instruction in a file behind the link was installed (on the machine of the
  # install the link still leads there) and never read. The rule: one FAIL per symlink to a directory below
  # skills/<name>/, named by the path of the link below the root and by its target as the link carries it. 4
  # rejected, 2 accepted. shared/flow.md is a file outside skills/ with 'git push origin main' in a code block.
  #   tooldirlink:     skills/x/shared -> an absolute path outside the skill. Exactly one FAIL line, the one for the
  #                    link: checks 1 to 6 are green on this tree (measured: before the rule this fixture was
  #                    accepted), and the push behind the link is not reported, because nothing behind it is read
  #   tooldirlinkrel:  skills/x/shared -> ../../shared, a relative path that leaves the skill. In a project the link
  #                    leads nowhere (there is no shared/ beside its skills/), so check 4 is red on this tree as well -
  #                    the case wants the line for the link and the lines of check 4, the whole set
  #   tooldirlinkdeep: skills/x/references/more -> the same directory, one folder deeper -> rejected by that path
  #   tooldirlinkin:   skills/x/alias -> references, a folder of the same skill with no push in it. Rejected too: the
  #                    rule asks whether the entry is a link to a directory, not where it leads
  #   toolevalslink:   skills/x/evals -> the directory with the push. install.sh does not install the entry named
  #                    evals, so nothing of it reaches a project -> accepted
  #   toolfilelinkok:  skills/x/alias.md -> SKILL.md, a symlink to a file with no push in it -> accepted (a link to
  #                    a file stays allowed and is read: toolskilllink above)
  local why51='symlink to a directory inside a skill (issue #51: install.sh copies the link and not the files behind it, and check 7 does not read them - a skill carries its own files)'
  local why4='install.sh did not copy every entry of every skill (evals/ aside, hidden entries included)'
  cp -r "$t/listed" "$t/tooldirlink"
  mkdir -p "$t/tooldirlink/shared"
  printf '# flow\n\n```bash\ngit push origin main\n```\n' > "$t/tooldirlink/shared/flow.md"
  ln -s "$t/tooldirlink/shared" "$t/tooldirlink/skills/x/shared"
  tool_file_case "symlink inside a skill to a directory that holds a file with 'git push origin main'" "$t/tooldirlink" "FAIL: skills/x/shared -> $t/tooldirlink/shared: $why51" '#51' || rc=1
  cp -r "$t/listed" "$t/tooldirlinkrel"
  mkdir -p "$t/tooldirlinkrel/shared"
  printf '# flow\n\n```bash\ngit push origin main\n```\n' > "$t/tooldirlinkrel/shared/flow.md"
  ln -s ../../shared "$t/tooldirlinkrel/skills/x/shared"
  tool_file_case "relative symlink inside a skill to a directory outside it" "$t/tooldirlinkrel" "FAIL: $why4
FAIL: skills/x/shared -> ../../shared: $why51" '#51' || rc=1
  cp -r "$t/listed" "$t/tooldirlinkdeep"
  mkdir -p "$t/tooldirlinkdeep/shared" "$t/tooldirlinkdeep/skills/x/references"
  printf '# flow\n\n```bash\ngit push origin main\n```\n' > "$t/tooldirlinkdeep/shared/flow.md"
  ln -s "$t/tooldirlinkdeep/shared" "$t/tooldirlinkdeep/skills/x/references/more"
  tool_file_case "symlink to a directory one folder deep inside a skill" "$t/tooldirlinkdeep" "FAIL: skills/x/references/more -> $t/tooldirlinkdeep/shared: $why51" '#51' || rc=1
  cp -r "$t/listed" "$t/tooldirlinkin"
  mkdir -p "$t/tooldirlinkin/skills/x/references"
  printf '# flow\n\nno command here\n' > "$t/tooldirlinkin/skills/x/references/flow.md"
  ln -s references "$t/tooldirlinkin/skills/x/alias"
  tool_file_case "symlink inside a skill to a folder of the same skill" "$t/tooldirlinkin" "FAIL: skills/x/alias -> references: $why51" '#51' || rc=1
  cp -r "$t/listed" "$t/toolevalslink"
  mkdir -p "$t/toolevalslink/shared"
  printf '# flow\n\n```bash\ngit push origin main\n```\n' > "$t/toolevalslink/shared/flow.md"
  ln -s "$t/toolevalslink/shared" "$t/toolevalslink/skills/x/evals"
  out="$(run_checks "$t/toolevalslink" 2>&1)" || {
    echo "selftest FAIL: a skill's evals that is a symlink to a directory (not installed) rejected (issue #51):"
    printf '%s\n' "$out"
    rc=1
  }
  cp -r "$t/listed" "$t/toolfilelinkok"
  ln -s SKILL.md "$t/toolfilelinkok/skills/x/alias.md"
  out="$(run_checks "$t/toolfilelinkok" 2>&1)" || {
    echo "selftest FAIL: symlink inside a skill to a file with no push in it rejected (issue #51):"
    printf '%s\n' "$out"
    rc=1
  }
  # option cases (issue #25): the gate file itself, started with --push-main - check 7 alone, as a readout. One
  # "FILE:LINE: command" line per report, then a last line with the counts; exit 0 nothing reported, 1 reported,
  # 2 a FILE that is no readable file (nothing is read then). The whole output is compared, line for line.
  #   pm/hit.md:   a push to main at line 3
  #   pm/two.md:   one at line 1 and a wrapped one that starts at line 5
  #   pm/clean.md: a push of a branch, and main in prose only
  #   pm/sub/:     a directory - no file; also the empty directory the starts without a FILE are made in
  #   pmrepo / pmrepobad: the good fixture plus scripts/ with a copy of this file, for the start without a FILE. It
  #                reads README.md and what install.sh installs from the repo the gate file belongs to, wherever it
  #                is started. pmrepobad carries a push to main in skills/x/references/flow.md (installed, so it is
  #                reported) and in skills/x/evals/e.md (not installed, so it is not read and not counted)
  # 8 starts with --push-main: 3 with files that can be read (one with a report, one without, three files in one
  # start), 3 with a FILE that is none (missing, missing next to one with a report, a directory), 2 without a FILE
  # (pmrepo, pmrepobad). Then 1 start with --help: exit 0, the header from its first line on, the option named in it.
  local helpout
  mkdir -p "$t/pm/sub"
  printf '# f\n\ngit push origin main\n' > "$t/pm/hit.md"
  printf 'git push origin HEAD:main\n\n```bash\ngit fetch origin\ngit push -u origin \\\n  main\n```\n' > "$t/pm/two.md"
  printf 'The change reaches `main` through a pull request, never by a push to `main`:\n\n```bash\ngit push -u origin feat/x\n```\n' > "$t/pm/clean.md"
  push_main_case "one file with a push to main" "$t/pm" "$SELF" 1 \
    $'hit.md:3: git push origin main\npush-main: FOUND hits=1 files=1' hit.md || rc=1
  push_main_case "one file without one" "$t/pm" "$SELF" 0 'push-main: ok files=1' clean.md || rc=1
  push_main_case "three files, three reports in two of them" "$t/pm" "$SELF" 1 \
    $'hit.md:3: git push origin main\ntwo.md:1: git push origin HEAD:main\ntwo.md:5: git push -u origin main\npush-main: FOUND hits=3 files=3' clean.md hit.md two.md || rc=1
  push_main_case "a FILE that does not exist" "$t/pm" "$SELF" 2 'gate.sh: --push-main: not a readable file: nope.md' nope.md || rc=1
  push_main_case "a FILE that does not exist next to one with a report" "$t/pm" "$SELF" 2 \
    'gate.sh: --push-main: not a readable file: nope.md' hit.md nope.md || rc=1
  push_main_case "a directory as FILE" "$t/pm" "$SELF" 2 'gate.sh: --push-main: not a readable file: sub' sub || rc=1
  cp -r "$t/good" "$t/pmrepo"
  mkdir -p "$t/pmrepo/scripts"
  cp "$SELF" "$t/pmrepo/scripts/gate.sh"
  cp -r "$t/pmrepo" "$t/pmrepobad"
  mkdir -p "$t/pmrepobad/skills/x/references" "$t/pmrepobad/skills/x/evals"
  printf '# flow\n\ngit push origin main\n' > "$t/pmrepobad/skills/x/references/flow.md"
  printf 'git push origin main\n' > "$t/pmrepobad/skills/x/evals/e.md"
  push_main_case "no FILE, a repo without a push to main" "$t/pm/sub" "$t/pmrepo/scripts/gate.sh" 0 'push-main: ok files=4' || rc=1
  push_main_case "no FILE, a repo with one in an installed skill file and one in evals/" "$t/pm/sub" "$t/pmrepobad/scripts/gate.sh" 1 \
    $'skills/x/references/flow.md:3: git push origin main\npush-main: FOUND hits=1 files=5' || rc=1
  helpout="$(cd "$t/pm/sub" && bash "$SELF" --help 2>&1)" || { echo "selftest FAIL: --help does not end with exit 0"; rc=1; }
  [ "${helpout%%$'\n'*}" = "gate.sh — offline gate for tgc-dev-tools (fleet board gate, routing[\"gates\"])." ] || {
    echo "selftest FAIL: --help does not start with the first line of the header, but with: ${helpout%%$'\n'*}"; rc=1; }
  printf '%s\n' "$helpout" | grep -q -F -- 'scripts/gate.sh --push-main [FILE ...]' || { echo "selftest FAIL: --help does not name --push-main [FILE ...]"; rc=1; }
  # option cases (issue #66): the gate file itself, started with --fences - the code fences as the fence rule of
  # FENCE_AWK reads them, as a readout. One "FILE:LINE: kind: text" line per named line, then a last line with the
  # counts; exit 0 when every FILE was read, 2 for a FILE that is no readable file (nothing is read then). The whole
  # output is compared, line for line. F is the fence of three backticks, F4 one of four.
  #   fx/all.md, 13 lines: a block of four backticks with a line of three inside (1-3), a block of three backticks
  #                with a line of tildes and a line with text behind the run inside (4-7), a line of three backticks
  #                behind four blanks, which is no fence line (8), a block of four tildes with an info string, a line
  #                of three inside and closed by five (9-11), and a block that nothing closes (12-13)
  #   fx/crlf.md:  a block of four backticks whose lines end in a carriage return, with a line of three inside
  #   fx/last.md:  a block of four backticks that nothing closes - one line that is long and unclosed
  #   fx/indent.md, 9 lines: fence lines with blanks in front - a block opened behind three blanks and closed behind
  #                one (1-3), a block of four tildes opened behind two blanks, with a line of three behind three
  #                blanks inside, closed behind none (4-7), and a block opened behind one blank whose only other fence
  #                line has four blanks in front, so it is content and the block is unclosed (8-9). The first form of
  #                fence_run read none of these lines as a fence line
  #   pm/clean.md: one plain block (the fixture of --push-main above); pmrepo: the README of the fixtures has one
  # 7 starts with --fences: 4 with files that can be read (the 13 lines, a plain block, three files in one start,
  # the indented fence lines), 2 with a FILE that is none (missing next to one that can be read, a directory),
  # 1 without a FILE (pmrepo). F4 is the fence of four backticks of form 12 above; it was declared here before the
  # block cases of form 12 existed (superseded, kept as a comment): local F4=(four backticks in single quotes)
  mkdir -p "$t/fx/sub"
  printf '%s\n' "$F4" "$F" "$F4" "$F" '~~~' "${F}bash" "$F" "    $F" '~~~~ info' '~~~' '~~~~~' "$F" 'text' > "$t/fx/all.md"
  printf '%s\r\n' "$F4" 'git switch main' "$F" 'git push' "$F4" > "$t/fx/crlf.md"
  printf '%s\n' 'text' "$F4" 'git push' > "$t/fx/last.md"
  fences_case "13 lines with every kind" "$t/fx" "$SELF" 0 \
    "all.md:1: long: $F4"$'\n'"all.md:2: inner: $F"$'\n'"all.md:5: inner: ~~~"$'\n'"all.md:6: inner: ${F}bash"$'\n'"all.md:9: long: ~~~~ info"$'\n'"all.md:10: inner: ~~~"$'\n'"all.md:12: unclosed: $F"$'\n'"fences: files=1 blocks=4 long=2 inner=4 unclosed=1" all.md || rc=1
  fences_case "one plain block" "$t/pm" "$SELF" 0 'fences: files=1 blocks=1 long=0 inner=0 unclosed=0' clean.md || rc=1
  fences_case "three files in one start, one with carriage returns" "$t" "$SELF" 0 \
    "fx/crlf.md:1: long: $F4"$'\n'"fx/crlf.md:3: inner: $F"$'\n'"fx/last.md:2: long, unclosed: $F4"$'\n'"fences: files=3 blocks=3 long=2 inner=1 unclosed=1" fx/crlf.md pm/clean.md fx/last.md || rc=1
  printf '%s\n' "   $F" 'text' " $F" '  ~~~~' '   ~~~' 'text' '~~~~' " $F" "    $F" > "$t/fx/indent.md"
  fences_case "fence lines with one to three blanks in front" "$t/fx" "$SELF" 0 \
    "indent.md:4: long:   ~~~~"$'\n'"indent.md:5: inner:    ~~~"$'\n'"indent.md:8: unclosed:  $F"$'\n'"fences: files=1 blocks=3 long=1 inner=1 unclosed=1" indent.md || rc=1
  fences_case "a FILE that does not exist next to one that can be read" "$t/fx" "$SELF" 2 \
    'gate.sh: --fences: not a readable file: nope.md' all.md nope.md || rc=1
  fences_case "a directory as FILE" "$t/fx" "$SELF" 2 'gate.sh: --fences: not a readable file: sub' sub || rc=1
  fences_case "no FILE, the files check 7 reads in a repo" "$t/pm/sub" "$t/pmrepo/scripts/gate.sh" 0 \
    'fences: files=4 blocks=1 long=0 inner=0 unclosed=0' || rc=1
  # 2 more starts with --fences (issue #69), 9 in all: a line that starts with a run of backticks and carries a
  # backtick behind the run is no fence line - it opens nothing and is not named as an inner line either.
  #   fx/inline.md, 5 lines: the fixture of the issue - a heading, an empty line, a sentence that starts with inline
  #                code in three backticks, prose, a push. No block (before: one that nothing closed, at line 3)
  #   fx/mixed.md, 8 lines: such a sentence (1), a plain block with a line inside that starts with three backticks
  #                and carries one more (2-4), a block of tildes whose info string carries a backtick (5-6), a line of
  #                four backticks with one behind them (7) and a block with an info string that nothing closes (8).
  #                Three blocks, one unclosed (before: four, read inverted from line 1 on - line 7 long and unclosed,
  #                line 8 an inner line)
  printf '%s\n' '# Update' '' "${F}git switch main${F} is how the update starts." 'Some prose.' 'git push' > "$t/fx/inline.md"
  printf '%s\n' "${F}x${F} text" "$F" "${F}a\`b" "$F" '~~~ a`b' '~~~' "${F4} a \` b" "${F}bash" > "$t/fx/mixed.md"
  fences_case "a sentence that starts with inline code in three backticks" "$t/fx" "$SELF" 0 \
    'fences: files=1 blocks=0 long=0 inner=0 unclosed=0' inline.md || rc=1
  fences_case "8 lines, backtick runs with a backtick behind them outside and inside a block" "$t/fx" "$SELF" 0 \
    "mixed.md:8: unclosed: ${F}bash"$'\n'"fences: files=1 blocks=3 long=0 inner=0 unclosed=1" mixed.md || rc=1
  printf '%s\n' "$helpout" | grep -q -F -- 'scripts/gate.sh --fences [FILE ...]' || { echo "selftest FAIL: --help does not name --fences [FILE ...]"; rc=1; }
  # link cases (issue #29): the gate file itself, started with bash in an empty directory, directly and through
  # symlinks - the last line and the exit code are those of the repo the file belongs to, never of the directory
  # above the link.
  #   linkrepo / linkrepobad: the good fixture plus scripts/ with a copy of this file and of readme-listing-check.sh;
  #                           linkrepobad has an agent without frontmatter (check 2 red)
  #   overgood / overbad:     a passing and a failing tree WITHOUT scripts/ - the directories the links are put into.
  #                           A gate that takes the directory above the link reads these instead: green on the
  #                           link to linkrepobad, red on the link to linkrepo
  # 10 starts: 2 direct, 2 through a file link in an otherwise empty directory (the measured case of the issue), 2
  # through a file link inside overgood / overbad, 1 through a link with a relative target, 1 through a link to a
  # link, 2 through a link to the scripts/ directory. Every rejected start must name the agent of linkrepobad.
  local why='FAIL: frontmatter name/description: agents/a.md'
  cp -r "$t/good" "$t/linkrepo"
  mkdir -p "$t/linkrepo/scripts"
  cp "$SELF" "$t/linkrepo/scripts/gate.sh"
  cp "$(dirname "$SELF")/readme-listing-check.sh" "$t/linkrepo/scripts/readme-listing-check.sh"
  printf '\nGate: `scripts/gate.sh` with `scripts/readme-listing-check.sh`\n' >> "$t/linkrepo/README.md"
  cp -r "$t/linkrepo" "$t/linkrepobad"
  printf 'no frontmatter\n' > "$t/linkrepobad/agents/a.md"
  cp -r "$t/good" "$t/overgood"
  cp -r "$t/good" "$t/overbad"
  printf 'no frontmatter\n' > "$t/overbad/agents/a.md"
  mkdir -p "$t/cwd" "$t/lone/sub" "$t/overgood/sub" "$t/overbad/sub" "$t/rel/sub" "$t/chain/sub"
  ln -s "$t/linkrepo/scripts/gate.sh" "$t/lone/sub/gate.sh"
  ln -s "$t/linkrepobad/scripts/gate.sh" "$t/lone/sub/gate-bad.sh"
  ln -s "$t/linkrepobad/scripts/gate.sh" "$t/overgood/sub/gate.sh"
  ln -s "$t/linkrepo/scripts/gate.sh" "$t/overbad/sub/gate.sh"
  ln -s ../../linkrepobad/scripts/gate.sh "$t/rel/sub/gate.sh"
  ln -s "$t/rel/sub/gate.sh" "$t/chain/sub/gate.sh"
  ln -s "$t/linkrepobad/scripts" "$t/overgood/scripts"
  ln -s "$t/linkrepo/scripts" "$t/overbad/scripts"
  link_case "direct start, good tree" "$t/cwd" "$t/linkrepo/scripts/gate.sh" 'gate: ok exit=0' || rc=1
  link_case "direct start, broken tree" "$t/cwd" "$t/linkrepobad/scripts/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "file link in an empty directory, good tree" "$t/cwd" "$t/lone/sub/gate.sh" 'gate: ok exit=0' || rc=1
  link_case "file link in an empty directory, broken tree" "$t/cwd" "$t/lone/sub/gate-bad.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "file link to the broken tree, placed inside a passing tree" "$t/cwd" "$t/overgood/sub/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "file link to the good tree, placed inside a failing tree" "$t/cwd" "$t/overbad/sub/gate.sh" 'gate: ok exit=0' || rc=1
  link_case "file link with a relative target, broken tree" "$t/cwd" "$t/rel/sub/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "link to a link, broken tree" "$t/cwd" "$t/chain/sub/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "link to scripts/ of the broken tree, placed inside a passing tree" "$t/cwd" "$t/overgood/scripts/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "link to scripts/ of the good tree, placed inside a failing tree" "$t/cwd" "$t/overbad/scripts/gate.sh" 'gate: ok exit=0' || rc=1
  # installer link cases (issue #35): install.sh of this repo as linkrepo carries it (agent a, command c, skill x),
  # started with bash in an empty directory, directly and through symlinks, each time into a destination of its
  # own below the temp dir. Every start ends with exit 0 and installs exactly the three files of linkrepo.
  #   instdecoy: a directory with agents/, commands/ and skills/ of its own (one file "decoy" in each) - where one
  #              link is put. An installer that takes the directory of the link installs the decoy files from
  #              there and ends with exit 0; from an empty directory it stops with a cp error (the measured case).
  # 6 starts: 1 direct, 1 through a file link in an otherwise empty directory, 1 through a file link inside
  # instdecoy, 1 through a link with a relative target, 1 through a link to a link, 1 through a link to the repo
  # directory.
  local inst=$'./agents/a.md\n./commands/c.md\n./skills/x/SKILL.md'
  mkdir -p "$t/instdecoy/agents" "$t/instdecoy/commands" "$t/instdecoy/skills/decoy" "$t/instdir" "$t/instdest"
  printf -- '---\nname: decoy\ndescription: d\n---\nbody\n' > "$t/instdecoy/agents/decoy.md"
  printf 'cmd\n' > "$t/instdecoy/commands/decoy.md"
  printf -- '---\nname: decoy\ndescription: d\n---\nbody\n' > "$t/instdecoy/skills/decoy/SKILL.md"
  ln -s "$t/linkrepo/install.sh" "$t/lone/sub/install.sh"
  ln -s "$t/linkrepo/install.sh" "$t/instdecoy/install.sh"
  ln -s ../../linkrepo/install.sh "$t/rel/sub/install.sh"
  ln -s "$t/rel/sub/install.sh" "$t/chain/sub/install.sh"
  ln -s "$t/linkrepo" "$t/instdir/repo"
  install_link_case "installer, direct start" "$t/cwd" "$t/linkrepo/install.sh" "$t/instdest/direct/.claude" "$inst" || rc=1
  install_link_case "installer, file link in an empty directory" "$t/cwd" "$t/lone/sub/install.sh" "$t/instdest/lone/.claude" "$inst" || rc=1
  install_link_case "installer, file link placed in a directory with agents/, commands/, skills/ of its own" "$t/cwd" "$t/instdecoy/install.sh" "$t/instdest/decoy/.claude" "$inst" || rc=1
  install_link_case "installer, file link with a relative target" "$t/cwd" "$t/rel/sub/install.sh" "$t/instdest/rel/.claude" "$inst" || rc=1
  install_link_case "installer, link to a link" "$t/cwd" "$t/chain/sub/install.sh" "$t/instdest/chain/.claude" "$inst" || rc=1
  install_link_case "installer, link to the repo directory" "$t/cwd" "$t/instdir/repo/install.sh" "$t/instdest/dir/.claude" "$inst" || rc=1
  # installer count cases (issue #54): install.sh of this repo beside agents/, commands/ and skills/ that also hold
  # entries the install does not copy. Started with bash in an empty directory, each time into a destination below
  # the temp dir that does not exist. The line before the last ("Done. Installed N agents, M commands, K skills.")
  # must count what was copied - as many as there are "[agent]", "[command]" and "[skill]" lines above it - and the
  # entries that are not copied must not be in the destination.
  #   countsrc/clean: agent a.md, command c.md, skill x and nothing else -> 1, 1, 1. The control: here the count of
  #                   the source folders and the count of what was copied are the same number
  #   countsrc/notes: the same plus agents/NOTES.txt, commands/NOTES.txt and skills/loose.txt - the measured case
  #                   of the issue -> 1, 1, 1 (before: "Installed 2 agents, 2 commands, 1 skills.")
  #   countsrc/mixed: agents a.md and b.md, command c.md, skills x and y, plus agents/NOTES.txt, a directory
  #                   agents/drafts/, commands/NOTES.txt and commands/README (no ending) -> 2, 1, 2 (before:
  #                   "Installed 4 agents, 3 commands, 2 skills."). Three different numbers, so a line that prints
  #                   one counter three times is seen
  #   countsrc/none:  agents/ with NOTES.txt only, command c.md, skills/ with loose.txt only - nothing to install in
  #                   two of the three folders, which the loops skip since issue #53 -> 0, 1, 0 and nothing on
  #                   stderr (before: "Installed 1 agents, 1 commands, 0 skills." behind an error line of ls, whose
  #                   pattern skills/*/ had matched nothing)
  # 4 starts: 1 on a source with nothing but what is installed, 3 on a source with entries that are not installed.
  mkdir -p "$t/countsrc/none/agents" "$t/countsrc/none/commands" "$t/countsrc/none/skills"
  cp "$(dirname "$SELF")/../install.sh" "$t/countsrc/none/install.sh"
  printf 'notes, not an agent\n' > "$t/countsrc/none/agents/NOTES.txt"
  printf 'cmd\n' > "$t/countsrc/none/commands/c.md"
  printf 'a loose file, not a skill\n' > "$t/countsrc/none/skills/loose.txt"
  local cinst cs
  cinst="$(dirname "$SELF")/../install.sh"
  for cs in clean notes mixed; do
    mkdir -p "$t/countsrc/$cs/agents" "$t/countsrc/$cs/commands" "$t/countsrc/$cs/skills/x"
    cp "$cinst" "$t/countsrc/$cs/install.sh"
    printf -- '---\nname: a\ndescription: d\n---\nbody\n' > "$t/countsrc/$cs/agents/a.md"
    printf 'cmd\n' > "$t/countsrc/$cs/commands/c.md"
    printf -- '---\nname: x\ndescription: d\n---\nbody\n' > "$t/countsrc/$cs/skills/x/SKILL.md"
  done
  for cs in notes mixed; do
    printf 'notes, not an agent\n' > "$t/countsrc/$cs/agents/NOTES.txt"
    printf 'notes, not a command\n' > "$t/countsrc/$cs/commands/NOTES.txt"
  done
  printf 'a loose file, not a skill\n' > "$t/countsrc/notes/skills/loose.txt"
  mkdir -p "$t/countsrc/mixed/agents/drafts" "$t/countsrc/mixed/skills/y"
  printf -- '---\nname: b\ndescription: d\n---\nbody\n' > "$t/countsrc/mixed/agents/b.md"
  printf 'no ending, not a command\n' > "$t/countsrc/mixed/commands/README"
  printf -- '---\nname: y\ndescription: d\n---\nbody\n' > "$t/countsrc/mixed/skills/y/SKILL.md"
  install_count_case "installer, Done line on a source with nothing but what is installed" "$t/cwd" "$t/countsrc/clean" "$t/countdest/clean/.claude" 1 1 1 "$inst" || rc=1
  install_count_case "installer, Done line with a NOTES.txt in agents/ and commands/ and a loose file in skills/" "$t/cwd" "$t/countsrc/notes" "$t/countdest/notes/.claude" 1 1 1 "$inst" || rc=1
  install_count_case "installer, Done line with files and a directory in agents/ and commands/ that are no *.md" "$t/cwd" "$t/countsrc/mixed" "$t/countdest/mixed/.claude" 2 1 2 \
    $'./agents/a.md\n./agents/b.md\n./commands/c.md\n./skills/x/SKILL.md\n./skills/y/SKILL.md' || rc=1
  install_count_case "installer, Done line with nothing to install in agents/ and skills/" "$t/cwd" "$t/countsrc/none" "$t/countdest/none/.claude" 0 1 0 './commands/c.md' || rc=1
  # installer source cases (issue #45): install.sh of this repo in a directory that is not a checkout of it,
  # started with bash in an empty directory, each time with a destination below the temp dir that does not exist.
  # Every start ends with exit 1 and one line that names the source and what it lacks, and the destination still
  # does not exist afterwards (before, the installer had already made agents/, commands/ and skills/ in it).
  #   nosrc/none:     a copy of install.sh alone in a directory - the measured case of the issue
  #   nosrc/agents:   the good fixture's commands/ and skills/ beside it, no agents/
  #   nosrc/commands: the good fixture's agents/ and skills/ beside it, no commands/ (before, a.md was installed
  #                   and then the install stopped)
  #   nosrc/skills:   the good fixture's agents/ and commands/ beside it, no skills/
  # 4 starts: 1 with none of the three folders, 3 with exactly one of them missing.
  local srcinst miss keep
  srcinst="$(dirname "$SELF")/../install.sh"
  mkdir -p "$t/nosrc/none"
  cp "$srcinst" "$t/nosrc/none/install.sh"
  install_nosource_case "installer alone in a directory" "$t/cwd" "$t/nosrc/none" "$t/nosrcdest/none/.claude" "agents/, commands/, skills/" || rc=1
  for miss in agents commands skills; do
    mkdir -p "$t/nosrc/$miss"
    cp "$srcinst" "$t/nosrc/$miss/install.sh"
    for keep in agents commands skills; do
      [ "$keep" = "$miss" ] || cp -r "$t/good/$keep" "$t/nosrc/$miss/$keep"
    done
    install_nosource_case "installer in a source without $miss/" "$t/cwd" "$t/nosrc/$miss" "$t/nosrcdest/$miss/.claude" "$miss/" || rc=1
  done
  # installer empty-folder cases (issue #53): install.sh of this repo in a source that has agents/, commands/ and
  # skills/, where at least one of the three holds nothing to install - the three sources of the table in the issue.
  # Started with bash in an empty directory, each time with a destination below the temp dir that does not exist.
  # An empty folder means "nothing of that kind to install": every start ends with exit 0, without a line of cp in
  # its output, with what the source had installed and with no entry named "*" in the destination.
  #   emptysrc/all:      nothing in any of the three folders (before: exit 1 on a cp error)
  #   emptysrc/commands: agent a.md and skill x, commands/ empty (before: a.md installed, then exit 1 on a cp
  #                      error, skill x not installed - half an install)
  #   emptysrc/skills:   agent a.md and the commands c.md and c2.md, skills/ empty (before: exit 0, "Done", and a
  #                      skill directory named "*" in the destination)
  # 3 starts: 1 with all three folders empty, 1 with only commands/ empty, 1 with only skills/ empty.
  local e
  for e in all commands skills; do
    mkdir -p "$t/emptysrc/$e/agents" "$t/emptysrc/$e/commands" "$t/emptysrc/$e/skills"
    cp "$srcinst" "$t/emptysrc/$e/install.sh"
  done
  for e in commands skills; do
    printf -- '---\nname: a\ndescription: d\n---\nbody\n' > "$t/emptysrc/$e/agents/a.md"
  done
  mkdir -p "$t/emptysrc/commands/skills/x"
  printf -- '---\nname: x\ndescription: d\n---\nbody\n' > "$t/emptysrc/commands/skills/x/SKILL.md"
  printf 'cmd\n' > "$t/emptysrc/skills/commands/c.md"
  printf 'cmd 2\n' > "$t/emptysrc/skills/commands/c2.md"
  install_empty_case "installer in a source whose agents/, commands/ and skills/ are all empty" "$t/cwd" "$t/emptysrc/all" "$t/emptydest/all/.claude" \
    $'./agents\n./commands\n./skills' || rc=1
  install_empty_case "installer in a source with an empty commands/" "$t/cwd" "$t/emptysrc/commands" "$t/emptydest/commands/.claude" \
    $'./agents\n./agents/a.md\n./commands\n./skills\n./skills/x\n./skills/x/SKILL.md' || rc=1
  install_empty_case "installer in a source with an empty skills/" "$t/cwd" "$t/emptysrc/skills" "$t/emptydest/skills/.claude" \
    $'./agents\n./agents/a.md\n./commands\n./commands/c.md\n./commands/c2.md\n./skills' || rc=1
  # last line cases (issue #67): selftest_run - the step that runs the cases and prints the last line of the
  # selftest - over seven stand-ins for the cases. Each stand-in is a function that prints what a run of cases
  # prints and ends the way it ends; the output is passed through unchanged and one line follows it.
  #   ll_green:  a note, return 0                                      -> "selftest ok", exit 0
  #   ll_block:  the measured case of the issue - one failed block case, whose last line is a line of its fixture,
  #              return 1                                              -> "selftest FAILED fail_lines=1", exit 1
  #   ll_nine:   nine failed cases, return 1                           -> "selftest FAILED fail_lines=9", exit 1
  #   ll_norc:   a "selftest FAIL:" line, but return 0 (a case that did not set rc) -> FAILED fail_lines=1, exit 1
  #   ll_quiet:  return 1 and no line at all                           -> "selftest FAILED fail_lines=0", exit 1
  #   ll_abort:  the cases stop at an unset variable (set -u) after their first line -> FAILED fail_lines=0, exit 1
  #   ll_quoted: the words inside a line, not at its start, return 0   -> not counted: "selftest ok", exit 0
  # 7 runs: 2 green, 5 red.
  ll_green() { echo "note: check 3 cases skipped"; return 0; }
  ll_block() { echo "selftest FAIL: check 7 block case, reported line(s) want '2' got '':"; printf '    | %s\n' 'git switch main' 'git push'; return 1; }
  ll_nine() { local i; for i in 1 2 3 4 5 6 7 8 9; do echo "selftest FAIL: case $i"; done; return 1; }
  ll_norc() { echo "selftest FAIL: a case that did not set rc"; return 0; }
  ll_quiet() { return 1; }
  # shellcheck disable=SC2154  # ll_never_set is unset on purpose: the stand-in has to stop there
  ll_abort() { echo "before the unset variable"; : "$ll_never_set"; echo "behind the unset variable"; return 0; }
  ll_quoted() { echo "    | selftest FAIL: a line of a fixture"; echo "note: no selftest FAIL: line here"; return 0; }
  last_line_case "green run" ll_green 0 "note: check 3 cases skipped" "selftest ok" || rc=1
  last_line_case "one failed block case (the measured case)" ll_block 1 \
    "selftest FAIL: check 7 block case, reported line(s) want '2' got '':" "    | git switch main" "    | git push" \
    "selftest FAILED fail_lines=1" || rc=1
  last_line_case "nine failed cases" ll_nine 1 \
    "selftest FAIL: case 1" "selftest FAIL: case 2" "selftest FAIL: case 3" "selftest FAIL: case 4" "selftest FAIL: case 5" \
    "selftest FAIL: case 6" "selftest FAIL: case 7" "selftest FAIL: case 8" "selftest FAIL: case 9" \
    "selftest FAILED fail_lines=9" || rc=1
  last_line_case "a FAIL line and return code 0" ll_norc 1 "selftest FAIL: a case that did not set rc" "selftest FAILED fail_lines=1" || rc=1
  last_line_case "return code 1 and no line" ll_quiet 1 "selftest FAILED fail_lines=0" || rc=1
  last_line_case "cases that stop at an unset variable" ll_abort 1 "before the unset variable" "selftest FAILED fail_lines=0" || rc=1
  last_line_case "the words inside a line" ll_quoted 0 "    | selftest FAIL: a line of a fixture" "note: no selftest FAIL: line here" "selftest ok" || rc=1
  rm -rf "$t"
  # Superseded by issue #67 (selftest_run prints the last line, for both results): [ "$rc" -eq 0 ] && echo "selftest ok"
  return "$rc"
}

# issue #67: the cases run inside selftest_run, which prints the last line - "selftest ok" or "selftest FAILED ..."
# Superseded form: if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
if [ "${1:-}" = "--selftest" ]; then selftest_run selftest; exit $?; fi
# issue #25: the header of this file as the usage text, and check 7 alone as a readout
case "${1:-}" in
  -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$SELF"; exit 0 ;;
  --push-main) shift; push_main_readout "$@"; exit $? ;;
  # issue #66: the code fences as the fence rule reads them, as a readout
  --fences) shift; fence_readout "$@"; exit $? ;;
esac
# issue #29: SELF is resolved, so this is the repo the program file belongs to, however the gate was started
ROOT="$(cd -P "$(dirname "$SELF")/.." && pwd)"
if run_checks "$ROOT"; then echo "gate: ok"; else echo "gate: FAILED"; exit 1; fi
