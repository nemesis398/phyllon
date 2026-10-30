#!/usr/bin/env bash
# Checks that the skills the repository ships in .agents/skills/ and the links
# Claude Code reads them through in .claude/skills/ match one to one: every
# entry in .claude/skills/ is a relative symlink to the skill of the same name
# in .agents/skills/, and every skill there has its link. It checks the tree
# ROOT, by default the repository this script lives in, from any working
# directory. CI's scripts job runs it. Run it with:
#
#   scripts/ci/check-skill-links.sh [ROOT]
#
# A skill is a directory directly in .agents/skills/ with a SKILL.md. The
# check fails on:
#
# - a skill directory without a SKILL.md;
# - an entry in .agents/skills/ that is a file or a symlink, because a skill
#   must live in the repository;
# - a skill without an entry of its name in .claude/skills/;
# - an entry in .claude/skills/ that is not a symlink: a copy there would drift
#   from the shipped skill and hide it;
# - a symlink with an absolute target, which resolves only on the machine that
#   made it;
# - a symlink that does not resolve, or resolves to anything but the skill of
#   its own name in .agents/skills/;
# - an empty or missing .agents/skills/, which means a wrong ROOT or a deleted
#   directory, not a pass.
#
# Names with spaces are checked like any other; whether a name is a valid
# skill name is not this script's concern.
#
# It prints each failure with the path it concerns and exits 0 when every
# skill is linked, 1 when something fails, and 2 on a usage error.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail
shopt -s nullglob dotglob

usage() {
	printf 'check-skill-links.sh: %s\n' "$@" >&2
	exit 2
}

(($# <= 1)) || usage "usage: check-skill-links.sh [ROOT]"
root="${1:-$(dirname "${BASH_SOURCE[0]}")/../..}"
[[ -d "$root" ]] || usage "$root is not a directory."
root="$(cd "$root" && pwd -P)"
skills="$root/.agents/skills"
links="$root/.claude/skills"

if [[ -L "$skills" || ! -d "$skills" ]]; then
	echo ".agents/skills: missing or not a directory"
	echo "check-skill-links.sh: found no skills in $root"
	exit 1
fi
skills_real="$(realpath -e -- "$skills")"

failures=()
count=0

for dir in "$skills"/*; do
	name="${dir##*/}"
	rel=".agents/skills/$name"
	if [[ -L "$dir" ]]; then
		failures+=("$rel: is a symlink; a skill must live in the repository")
		continue
	fi
	if [[ ! -d "$dir" ]]; then
		failures+=("$rel: is not a directory; a skill is a directory with a SKILL.md")
		continue
	fi
	count=$((count + 1))
	[[ -f "$dir/SKILL.md" ]] || failures+=("$rel: has no SKILL.md")
	# An entry that is there but no symlink is reported by the loop below.
	[[ -e "$links/$name" || -L "$links/$name" ]] ||
		failures+=("$rel: has no link .claude/skills/$name")
done
((count > 0)) || failures+=(".agents/skills: has no skills")

for link in "$links"/*; do
	name="${link##*/}"
	rel=".claude/skills/$name"
	if [[ ! -L "$link" ]]; then
		failures+=("$rel: is not a symlink; a skill lives in .agents/skills/ and is linked from here")
		continue
	fi
	target="$(readlink -- "$link")"
	if [[ "$target" == /* ]]; then
		failures+=("$rel: links to the absolute path $target; link to ../../.agents/skills/$name")
		continue
	fi
	if ! resolved="$(realpath -e -- "$link" 2>/dev/null)"; then
		failures+=("$rel: links to $target, which does not exist")
		continue
	fi
	[[ "$resolved" == "$skills_real/$name" ]] ||
		failures+=("$rel: links to $target, not to the skill .agents/skills/$name")
done

if ((${#failures[@]} > 0)); then
	printf '%s\n' "${failures[@]}"
	echo "check-skill-links.sh: ${#failures[@]} problem(s) with the skill links"
	exit 1
fi
if ((count == 1)); then
	echo "check-skill-links.sh: 1 skill, linked from .claude/skills/"
else
	echo "check-skill-links.sh: $count skills, each linked from .claude/skills/"
fi
