#!/usr/bin/env bash
# Checks that the module map, docs/map.md, and the modules of src/ match one to
# one: every module has its heading in the map, and every heading in the map
# has its module. It checks the tree ROOT, by default the repository this
# script lives in, from any working directory. CI's scripts job runs it. Run it
# with:
#
#   scripts/ci/check-map.sh [ROOT]
#
# A module is a file src/NAME.rs other than lib.rs and main.rs, or a directory
# src/NAME/, directly in src/. Deeper files and directories are submodules and
# belong to the entry of the module that holds them. A directory counts
# without a mod.rs, because a directory the map does not name is a decision
# to take, not to skip, and src/NAME.rs next to src/NAME/ is one module. Other
# files and names that start with a dot are no modules.
#
# An entry is a line that is exactly "## `NAME`": level two, one space, the
# name in backticks, nothing after it but blanks. The case of NAME counts. A
# line in another form, such as "## NAME" or "### `NAME`", is no entry, so a
# module it was meant for is reported as lacking one. Lines inside a fenced
# code block (``` or ~~~) are no entries either, so the map can show the form
# of a heading. The check fails on:
#
# - a module without an entry;
# - an entry without a module;
# - an entry that appears twice;
# - a symlink in src/ that leads nowhere, which the check cannot read;
# - a missing or empty src/, which means a wrong ROOT or a deleted tree, and
#   a missing docs/map.md.
#
# Known limitation: the check does not parse HTML comments, so a heading inside
# <!-- ... --> counts as an entry. Keep the map free of commented-out headings.
#
# It prints each failure with the path it concerns and exits 0 when the map
# and the modules match, 1 when something fails, and 2 on a usage error.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail
shopt -s nullglob

usage() {
	printf 'check-map.sh: %s\n' "$@" >&2
	exit 2
}

(($# <= 1)) || usage "usage: check-map.sh [ROOT]"
# An empty argument is a mistake, not a request for the default.
(($# == 0)) || [[ -n "$1" ]] || usage "ROOT is empty; omit it to check this repository."
root="${1:-$(dirname "${BASH_SOURCE[0]}")/../..}"
[[ -d "$root" ]] || usage "$root is not a directory."
root="$(CDPATH='' cd -- "$root" && pwd -P)"
src="$root/src"
map="$root/docs/map.md"

# The backtick, spelled out so that the patterns below stay readable.
tick=$'\x60'
heading_re="^## ${tick}([^${tick}]+)${tick}[[:space:]]*\$"
fence_open_re="^ {0,3}(${tick}{3,}|~{3,})"
fence_close_re="^ {0,3}(${tick}+|~+)[[:space:]]*\$"

failures=()
# Set when the comparison cannot run at all.
fatal=""
mod_names=()
mod_paths=()
rust_entries=0

if [[ -d "$src" ]]; then
	for entry in "$src"/*; do
		base="${entry##*/}"
		if [[ -L "$entry" && ! -e "$entry" ]]; then
			failures+=("src/$base: is a symlink that leads nowhere")
			continue
		fi
		if [[ -d "$entry" ]]; then
			rust_entries=$((rust_entries + 1))
			name="$base"
			path="src/$base/"
		elif [[ -f "$entry" && "$base" == *.rs ]]; then
			rust_entries=$((rust_entries + 1))
			[[ "$base" != lib.rs && "$base" != main.rs ]] || continue
			name="${base%.rs}"
			path="src/$base"
		else
			continue
		fi
		# src/NAME.rs and src/NAME/ together are one module, named by the file.
		for i in "${!mod_names[@]}"; do
			if [[ "${mod_names[$i]}" == "$name" ]]; then
				mod_paths[i]="src/$base"
				continue 2
			fi
		done
		mod_names+=("$name")
		mod_paths+=("$path")
	done
	((rust_entries > 0)) || {
		failures+=("src: has no Rust files or modules")
		fatal=1
	}
else
	failures+=("src: missing or not a directory")
	fatal=1
fi
[[ -f "$map" ]] || {
	failures+=("docs/map.md: missing or not a file")
	fatal=1
}

if [[ -n "$fatal" ]]; then
	printf '%s\n' "${failures[@]}"
	echo "check-map.sh: ${#failures[@]} problem(s) with docs/map.md"
	exit 1
fi

# The entries of the map, with the line each is on.
head_names=()
head_lines=()
fence=""
lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
	lineno=$((lineno + 1))
	if [[ -n "$fence" ]]; then
		# A fence ends with a run of its own character that is at least as long.
		if [[ "$line" =~ $fence_close_re ]]; then
			run="${BASH_REMATCH[1]}"
			if [[ "${run:0:1}" == "${fence:0:1}" ]] && ((${#run} >= ${#fence})); then
				fence=""
			fi
		fi
	elif [[ "$line" =~ $fence_open_re ]]; then
		fence="${BASH_REMATCH[1]}"
	elif [[ "$line" =~ $heading_re ]]; then
		head_names+=("${BASH_REMATCH[1]}")
		head_lines+=("$lineno")
	fi
done <"$map"

for i in "${!mod_names[@]}"; do
	found=""
	for name in "${head_names[@]}"; do
		if [[ "$name" == "${mod_names[$i]}" ]]; then
			found=1
			break
		fi
	done
	[[ -n "$found" ]] ||
		failures+=("${mod_paths[$i]}: has no heading ## ${tick}${mod_names[$i]}${tick} in docs/map.md")
done

for i in "${!head_names[@]}"; do
	name="${head_names[$i]}"
	first=""
	for ((j = 0; j < i; j++)); do
		if [[ "${head_names[$j]}" == "$name" ]]; then
			first="${head_lines[$j]}"
			break
		fi
	done
	if [[ -n "$first" ]]; then
		failures+=("docs/map.md:${head_lines[$i]}: duplicate heading ## ${tick}${name}${tick}, first at line $first")
		continue
	fi
	found=""
	for module in "${mod_names[@]}"; do
		if [[ "$module" == "$name" ]]; then
			found=1
			break
		fi
	done
	[[ -n "$found" ]] ||
		failures+=("docs/map.md:${head_lines[$i]}: heading ## ${tick}${name}${tick} has no module src/$name.rs or src/$name/")
done

if ((${#failures[@]} > 0)); then
	printf '%s\n' "${failures[@]}"
	echo "check-map.sh: ${#failures[@]} problem(s) with docs/map.md"
	exit 1
fi
case "${#mod_names[@]}" in
0) echo "check-map.sh: 0 modules in src/, so no heading to check" ;;
1) echo "check-map.sh: 1 module, with its heading in docs/map.md" ;;
*) echo "check-map.sh: ${#mod_names[@]} modules, each with a heading in docs/map.md" ;;
esac
