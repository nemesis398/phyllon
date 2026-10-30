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
# A skill is a directory directly in .agents/skills/ with a SKILL.md, and it
# must live in the repository: no symlink anywhere between ROOT and its
# SKILL.md. Each link points straight at its skill: its target is relative and,
# taken one hop from .claude/skills/, is .agents/skills/<its own name>, so a
# chain of links fails even when it ends at the skill. The check fails on:
#
# - a skill directory without a SKILL.md, or with a SKILL.md that is a symlink;
# - an entry in .agents/skills/ that is a file or a symlink;
# - an .agents/skills/ or .claude/skills/ that resolves outside ROOT, such as
#   through a symlinked .agents;
# - a skill without an entry of its name in .claude/skills/;
# - an entry in .claude/skills/ that is not a symlink: a copy there would drift
#   from the shipped skill and hide it;
# - a symlink with an absolute target, which resolves only on the machine that
#   made it;
# - a symlink that does not resolve, or whose target is anything but the skill
#   of its own name in .agents/skills/;
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
# An empty argument is a mistake, not a request for the default.
(($# == 0)) || [[ -n "$1" ]] || usage "ROOT is empty; omit it to check this repository."
root="${1:-$(dirname "${BASH_SOURCE[0]}")/../..}"
[[ -d "$root" ]] || usage "$root is not a directory."
root="$(cd "$root" && pwd -P)"
skills="$root/.agents/skills"
links="$root/.claude/skills"

if [[ ! -d "$skills" ]]; then
	echo ".agents/skills: missing or not a directory"
	echo "check-skill-links.sh: found no skills in $root"
	exit 1
fi
# ROOT is already resolved, so any symlink on the way changes the path.
skills_real="$(realpath -e -- "$skills")"
if [[ "$skills_real" != "$skills" ]]; then
	echo ".agents/skills: resolves outside the repository, to $skills_real"
	echo "check-skill-links.sh: 1 problem(s) with the skill links"
	exit 1
fi

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
	if [[ -L "$dir/SKILL.md" ]]; then
		failures+=("$rel/SKILL.md: is a symlink; a skill must live in the repository")
	elif [[ ! -f "$dir/SKILL.md" ]]; then
		failures+=("$rel: has no SKILL.md")
	fi
	# An entry that is there but no symlink is reported by the loop below.
	[[ -e "$links/$name" || -L "$links/$name" ]] ||
		failures+=("$rel: has no link .claude/skills/$name")
done
((count > 0)) || failures+=(".agents/skills: has no skills")

entries=()
if [[ -d "$links" ]]; then
	links_real="$(realpath -e -- "$links")"
	if [[ "$links_real" == "$links" ]]; then
		entries=("$links"/*)
	else
		failures+=(".claude/skills: resolves outside the repository, to $links_real")
	fi
fi

for link in "${entries[@]}"; do
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
	if [[ ! -e "$link" ]]; then
		failures+=("$rel: links to $target, which does not exist")
		continue
	fi
	# The first hop, taken without following any further link.
	hop="$(realpath -m -s -- "$links/$target")"
	[[ "$hop" == "$skills/$name" ]] ||
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
