#!/usr/bin/env bash
# The Claude Code PostToolUse hook for Edit, MultiEdit and Write. It formats the
# edited file with rustfmt when it is a Rust file, so the agent never fights
# the format step of the gate. Claude Code passes the event as JSON on stdin;
# this hook reads tool_input.file_path from it with jq. It leaves alone files
# outside this repository: the project directory and its linked worktrees,
# which share its git directory.
#
# It always exits 0: formatting is a convenience, and the gate's
# cargo fmt --check is what enforces it. When jq or rustfmt is missing or
# rustfmt fails, it writes a note to stderr, which Claude Code shows only in
# its debug log.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

# No errexit, and an EXIT trap that forces 0, because no failure here may
# turn into a hook error.
set -uo pipefail
trap 'exit 0' EXIT

note() {
	printf 'format-edited: %s\n' "$*" >&2
	exit 0
}

input="$(cat)"

command -v jq >/dev/null 2>&1 || note "jq not found; not formatting."
file="$(jq -r '.tool_input.file_path // empty' <<<"$input")" ||
	note "could not read tool_input.file_path from the hook input."

[[ "$file" == *.rs && -f "$file" ]] || exit 0

project="${CLAUDE_PROJECT_DIR:-$(dirname "${BASH_SOURCE[0]}")/../..}"
own="$(git -C "$project" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
	note "$project is not a git work tree; not formatting $file."
common="$(git -C "$(dirname "$file")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
[[ -n "$common" && "$common" == "$own" ]] || exit 0

# Claude Code may start without the rustup directory on PATH.
if ! command -v cargo >/dev/null 2>&1 && [[ -d "${HOME:-}/.cargo/bin" ]]; then
	PATH="$HOME/.cargo/bin:$PATH"
fi
command -v rustfmt >/dev/null 2>&1 || note "rustfmt not found; not formatting $file."

# From the file's directory, rustup picks the toolchain that the file's
# project pins.
cd "$(dirname "$file")" || note "cannot enter the directory of $file."
rustfmt --edition 2024 -- "$file" || note "rustfmt failed on $file."
exit 0
