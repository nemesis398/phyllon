#!/usr/bin/env bash
# The Claude Code Stop hook. It runs the gate, scripts/check.sh, before the
# agent may stop, but only when a file the gate depends on changed since the
# last green run. It exits 0 to let the agent stop and 2, with the gate's
# output on stderr, to send it back to work.
#
# The fingerprint is a SHA-256 over the path and the contents of every tracked
# and untracked (not ignored) file the gate depends on: Rust sources, Cargo
# manifests and lockfiles, the TOML files at the root, the workflows and the
# gate's own files. A green run writes it to target/.gate-green, a red run to
# target/.gate-red. A stop whose fingerprint matches target/.gate-green skips
# the gate. A stop that a red gate already sent back (stop_hook_active is true)
# with nothing changed since is let through with a note, so the agent is not
# sent back forever.
#
# Claude Code passes the event as JSON on stdin; this hook reads it with jq.
# Without jq it blocks the stop instead of letting an unchecked change through.
# So does any unexpected failure of this script.
#
# The gate runs in the work tree Claude is in (the cwd field) when that is a
# work tree of this repository, such as a linked worktree, and in this
# script's own checkout otherwise.
#
# Environment:
#   PHYLLON_GATE_CMD  path of an executable that replaces scripts/check.sh as
#                     the gate. Only scripts/hooks/test.sh sets it.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail
shopt -s inherit_errexit

# Exit 2 sends the agent back with stderr as the reason. Claude Code treats a
# Stop hook's exit 2 as a non-blocking error when stdout is empty and stderr
# says a file is missing ("No such file or directory"), which the gate's output
# can say, so every block also prints a line on stdout.
block() {
	echo "stop-gate: blocking the stop; the reason is on stderr"
	printf 'stop-gate: %s\n' "$@" >&2
	exit 2
}

# Fail closed: any other non-zero exit would let the agent stop unchecked.
# shellcheck disable=SC2329 # the EXIT trap calls it
on_exit() {
	local rc=$?
	if ((rc != 0 && rc != 2)); then
		echo "stop-gate: blocking the stop; the reason is on stderr"
		echo "stop-gate: the hook failed unexpectedly (exit $rc); see the error above" >&2
		exit 2
	fi
}
trap on_exit EXIT

input="$(cat)"

command -v jq >/dev/null 2>&1 ||
	block "jq not found, and this hook needs it to read Claude Code's input." \
		"Install jq (for example: sudo dnf install jq or brew install jq)."
active="$(jq -r '.stop_hook_active // false' <<<"$input")" ||
	block "could not read stop_hook_active from the hook input."
cwd="$(jq -r '.cwd // empty' <<<"$input")" ||
	block "could not read cwd from the hook input."

# Claude Code may start without the rustup directory on PATH.
if ! command -v cargo >/dev/null 2>&1 && [[ -d "${HOME:-}/.cargo/bin" ]]; then
	PATH="$HOME/.cargo/bin:$PATH"
fi

if command -v sha256sum >/dev/null 2>&1; then
	sha256() { sha256sum | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null 2>&1; then
	sha256() { shasum -a 256 | cut -d ' ' -f 1; }
else
	block "neither sha256sum nor shasum found."
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -n "$cwd" && -d "$cwd" ]]; then
	own="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"
	if top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" &&
		common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" &&
		[[ "$common" == "$own" ]]; then
		root="$top"
	fi
fi
cd "$root"

# In glob magic, "**/" also matches the top level and "*" stops at a slash.
gate_paths=(
	':(glob)**/*.rs'
	':(glob)**/Cargo.toml'
	':(glob)**/Cargo.lock'
	':(glob)*.toml'
	':(glob)**/.cargo/config.toml'
	':(glob).github/workflows/*'
	':(glob)scripts/check.sh'
	':(glob).githooks/**'
	':(glob).claude/settings.json'
	':(glob)scripts/hooks/*'
)

# One record per file, sorted by path: the path, then the hash of its contents.
# A tracked file deleted from the work tree is recorded as missing.
fingerprint() {
	local path
	git ls-files -z --cached --others --exclude-standard -- "${gate_paths[@]}" |
		LC_ALL=C sort -zu |
		while IFS= read -r -d '' path; do
			printf '%s\0' "$path"
			if [[ -L "$path" ]]; then
				printf 'symlink '
				readlink -- "$path" | sha256
			elif [[ -f "$path" ]]; then
				sha256 <"$path"
			else
				echo missing
			fi
		done |
		sha256
}

fp="$(fingerprint)"
green=target/.gate-green
red=target/.gate-red

if [[ -f "$green" && "$(<"$green")" == "$fp" ]]; then
	exit 0
fi

if [[ "$active" == true && -f "$red" && "$(<"$red")" == "$fp" ]]; then
	echo "stop-gate: the gate is still red and nothing it checks changed since;" \
		"letting the stop through. Run scripts/check.sh to see the errors." >&2
	exit 0
fi

gate="${PHYLLON_GATE_CMD:-scripts/check.sh}"
status=0
# The output goes to Claude, so no color codes: cargo reads CARGO_TERM_COLOR,
# rustfmt's diff only TERM.
output="$(CARGO_TERM_COLOR=never TERM=dumb "$gate" </dev/null 2>&1)" || status=$?

mkdir -p target
if ((status == 0)); then
	printf '%s\n' "$fp" >"$green"
	rm -f "$red"
	exit 0
fi

printf '%s\n' "$fp" >"$red"
rm -f "$green"
printf '%s\n' "$output" >&2
block "the gate ($gate) failed with exit $status. Fix what it reports above." \
	"Stop only once the gate is green."
