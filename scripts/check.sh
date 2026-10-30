#!/usr/bin/env bash
# The gate. The git pre-commit hook, the Claude Code Stop hook and CI all run
# this script, so a change passes the same checks everywhere. It exits 0 when
# every step passes and stops at the first failing step with that step's
# output and a non-zero exit.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail

# Run from the repository root, wherever the caller stands.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() {
	printf 'check.sh: %s\n' "$@" >&2
	exit 1
}

# Find every tool before the first step, so a missing one fails at once and not
# after minutes of clippy.
command -v cargo >/dev/null 2>&1 ||
	fail "cargo not found." \
		"Install rustup from https://rustup.rs and put ~/.cargo/bin on PATH;" \
		"the first cargo command then installs the toolchain rust-toolchain.toml pins."
toolchain="$(rustc --version)" ||
	fail "the toolchain rust-toolchain.toml pins is not installed. In the repository root, run:" \
		"  rustup toolchain install"
printf 'check.sh: %s\n' "$toolchain"
cargo fmt --version >/dev/null 2>&1 ||
	fail "rustfmt not found. rust-toolchain.toml lists it; with rustup run:" \
		"  rustup component add rustfmt"
cargo clippy --version >/dev/null 2>&1 ||
	fail "clippy not found. rust-toolchain.toml lists it; with rustup run:" \
		"  rustup component add clippy"
for tool in cargo-nextest cargo-shear cargo-deny; do
	command -v "$tool" >/dev/null 2>&1 ||
		fail "$tool not found. Install it with:" \
			"  cargo install --locked $tool"
done

steps=0
step() {
	steps=$((steps + 1))
	printf '\n==> %s\n' "$*"
	"$@" || fail "step failed: $*"
}

step cargo fmt --all --check
step cargo clippy --all-targets --locked -- -D warnings
step cargo nextest run --locked --no-tests=pass
step cargo test --doc --locked
step cargo shear
step cargo deny check bans licenses sources
printf '\ncheck.sh: all %d steps passed\n' "$steps"
