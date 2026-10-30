#!/usr/bin/env bash
# Checks a pull request title. Every pull request is squash merged, so its title
# becomes the commit on main and must be a conventional commit of at most 72
# characters: type, an optional scope in lowercase letters, digits and dashes,
# an optional "!" for a breaking change, then ": " and a summary. CI's pr-title
# job runs it with the title from the event. Run it with:
#
#   scripts/ci/check-pr-title.sh 'feat(web): add the shell'
#
# It exits 0 when the title passes, 1 when it does not and 2 on a usage error.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail

max=72
types='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
# [^[:space:]] is \S in POSIX extended regular expressions, which bash uses.
pattern="^($types)(\([a-z0-9-]+\))?!?: [^[:space:]].*\$"

if (($# != 1)); then
	echo "usage: check-pr-title.sh TITLE" >&2
	exit 2
fi
title="$1"

# Count characters, not bytes, so an umlaut counts once. Bash measures ${#var}
# in the current locale; C.UTF-8 ships with glibc.
LC_ALL=C.UTF-8
length=${#title}

fail() {
	printf 'check-pr-title.sh: %s\n' "$@" >&2
	exit 1
}

[[ "$title" != *$'\n'* ]] || fail "the title has more than one line."
[[ "$title" =~ $pattern ]] ||
	fail "'$title' is not a conventional commit. Write it as" \
		"  type(scope): summary" \
		"with type one of ${types//|/, }, an optional scope in lowercase letters," \
		"digits and dashes, and \"!\" before the colon for a breaking change."
((length <= max)) ||
	fail "the title has $length characters; the limit is $max, because it becomes" \
		"the subject of the squash commit."
echo "check-pr-title.sh: '$title' passes ($length characters)"
