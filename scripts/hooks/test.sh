#!/usr/bin/env bash
# Tests for stop-gate.sh, the Claude Code Stop hook. Each test builds its own
# git repository in a temporary directory, copies the hook into it, feeds it the
# JSON document Claude Code sends on stdin and checks the exit code, the output
# and the marker files in target/. A fake gate, named by PHYLLON_GATE_CMD,
# stands in for scripts/check.sh, so the tests run in seconds and never touch
# this checkout's target/. Run it with:
#
#   scripts/hooks/test.sh
#
# It prints PASS or FAIL per test and exits non-zero if any test failed.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail

hooks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Keep the user's git configuration (signing, hooks, templates) out of the
# temporary repositories.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# The hook runs whatever this names; each test points it at its own fake gate.
unset PHYLLON_GATE_CMD

scratch="$(mktemp -d -p "${TMPDIR:-/tmp}" phyllon-hook-tests.XXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT

# Set by new_repo and run_hook for the test that is running.
repo=""
gate=""
status=0
out=""
err=""

# Creates a repository with one tracked Rust file and the hook under test, and
# a fake gate outside it that passes. Changing the fake gate does not change the
# repository's fingerprint.
new_repo() {
	local dir
	dir="$(mktemp -d -p "$scratch")"
	repo="$dir/repo"
	gate="$dir/fake-gate"
	git init -q "$repo"
	mkdir -p "$repo/src" "$repo/scripts/hooks"
	printf 'fn main() {}\n' >"$repo/src/main.rs"
	git -C "$repo" add src/main.rs
	cp -p "$hooks_dir/stop-gate.sh" "$repo/scripts/hooks/" 2>/dev/null || true
	gate_passes
}

gate_passes() {
	printf '#!/usr/bin/env bash\necho "fake gate ran" >>"%s/calls"\nexit 0\n' \
		"$(dirname "$gate")" >"$gate"
	chmod +x "$gate"
}

gate_fails() {
	printf '#!/usr/bin/env bash\necho "fake gate ran" >>"%s/calls"\necho boom\nexit 1\n' \
		"$(dirname "$gate")" >"$gate"
	chmod +x "$gate"
}

gate_calls() {
	if [[ -f "$(dirname "$gate")/calls" ]]; then
		wc -l <"$(dirname "$gate")/calls" | tr -d ' '
	else
		echo 0
	fi
}

# Runs the hook from / with a Stop event for $1 (the cwd field) and $2 (the
# stop_hook_active field), and records the exit code, stdout and stderr.
run_hook() {
	local cwd="$1" active="$2" input
	input="$(jq -nc --arg cwd "$cwd" --argjson active "$active" \
		'{session_id: "test", hook_event_name: "Stop", cwd: $cwd, stop_hook_active: $active}')"
	status=0
	(cd / && PHYLLON_GATE_CMD="$gate" "$repo/scripts/hooks/stop-gate.sh" \
		<<<"$input" >"$scratch/out" 2>"$scratch/err") || status=$?
	out="$(cat "$scratch/out")"
	err="$(cat "$scratch/err")"
}

# Each check prints why it failed and returns non-zero, which fails the test.
expect_status() {
	[[ "$status" == "$1" ]] || {
		echo "  expected exit $1, got $status; stderr: $err"
		return 1
	}
}
expect_file() {
	[[ -f "$1" ]] || {
		echo "  expected $1 to exist"
		return 1
	}
}
expect_no_file() {
	[[ ! -e "$1" ]] || {
		echo "  expected $1 not to exist"
		return 1
	}
}
expect_calls() {
	[[ "$(gate_calls)" == "$1" ]] || {
		echo "  expected the gate to run $1 times, it ran $(gate_calls)"
		return 1
	}
}
expect_err() {
	[[ "$err" == *"$1"* ]] || {
		echo "  expected stderr to contain '$1', got: $err"
		return 1
	}
}

gate_green_lets_the_agent_stop() {
	new_repo
	run_hook "$repo" false
	expect_status 0
	expect_calls 1
	expect_file "$repo/target/.gate-green"
	expect_no_file "$repo/target/.gate-red"
}

gate_red_blocks_the_stop() {
	new_repo
	gate_fails
	run_hook "$repo" false
	expect_status 2
	expect_err boom
	expect_file "$repo/target/.gate-red"
	expect_no_file "$repo/target/.gate-green"
	# Claude Code lets a Stop hook's exit 2 through when stdout is empty and
	# stderr says a file is missing, which the gate's output can say.
	[[ -n "$out" ]] || {
		echo "  expected a line on stdout"
		return 1
	}
}

unchanged_files_skip_the_gate() {
	new_repo
	run_hook "$repo" false
	expect_status 0
	gate_fails
	run_hook "$repo" false
	expect_status 0
	expect_calls 1
}

a_repeated_red_stop_is_let_through() {
	new_repo
	gate_fails
	run_hook "$repo" false
	expect_status 2
	run_hook "$repo" true
	expect_status 0
	expect_calls 1
	expect_err "still red"
}

a_new_stop_after_a_red_one_runs_the_gate() {
	new_repo
	gate_fails
	run_hook "$repo" false
	expect_status 2
	run_hook "$repo" false
	expect_status 2
	expect_calls 2
}

a_repeated_red_stop_after_a_change_runs_the_gate() {
	new_repo
	gate_fails
	run_hook "$repo" false
	expect_status 2
	printf 'fn main() { println!("x"); }\n' >"$repo/src/main.rs"
	run_hook "$repo" true
	expect_status 2
	expect_calls 2
}

a_green_run_after_a_red_one_clears_the_red_marker() {
	new_repo
	gate_fails
	run_hook "$repo" false
	expect_status 2
	printf 'fn main() { println!("fixed"); }\n' >"$repo/src/main.rs"
	gate_passes
	run_hook "$repo" false
	expect_status 0
	expect_file "$repo/target/.gate-green"
	expect_no_file "$repo/target/.gate-red"
}

the_gate_runs_without_colors() {
	new_repo
	# shellcheck disable=SC2016 # the fake gate expands these, not this shell
	printf '#!/usr/bin/env bash\necho "TERM=$TERM color=$CARGO_TERM_COLOR"\nexit 1\n' >"$gate"
	TERM=xterm-256color CARGO_TERM_COLOR=always run_hook "$repo" false
	expect_status 2
	expect_err "TERM=dumb color=never"
}

a_changed_rust_file_runs_the_gate_again() {
	new_repo
	run_hook "$repo" false
	expect_status 0
	printf 'fn helper() {}\n' >"$repo/src/lib.rs"
	gate_fails
	run_hook "$repo" false
	expect_status 2
	expect_calls 2
	expect_no_file "$repo/target/.gate-green"
}

a_renamed_rust_file_runs_the_gate_again() {
	new_repo
	run_hook "$repo" false
	expect_status 0
	git -C "$repo" mv src/main.rs src/other.rs
	run_hook "$repo" false
	expect_status 0
	expect_calls 2
}

a_deleted_tracked_file_runs_the_gate_again() {
	new_repo
	run_hook "$repo" false
	expect_status 0
	rm "$repo/src/main.rs"
	gate_fails
	run_hook "$repo" false
	expect_status 2
	expect_calls 2
	expect_err boom
}

a_change_to_another_file_skips_the_gate() {
	new_repo
	run_hook "$repo" false
	expect_status 0
	printf '# notes\n' >"$repo/README.md"
	mkdir -p "$repo/docs"
	printf 'x = 1\n' >"$repo/docs/nested.toml"
	gate_fails
	run_hook "$repo" false
	expect_status 0
	expect_calls 1
}

a_linked_worktree_is_gated_in_its_own_tree() {
	new_repo
	git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
		commit -qm init
	local tree
	tree="$(mktemp -d -p "$scratch")"
	git -C "$repo" worktree add -q -b other "$tree"
	gate_fails
	run_hook "$tree" false
	expect_status 2
	expect_file "$tree/target/.gate-red"
	expect_no_file "$repo/target/.gate-red"
}

a_missing_jq_blocks_the_stop() {
	new_repo
	local bin="$scratch/bin-$BASHPID"
	mkdir -p "$bin"
	ln -s "$(command -v bash)" "$bin/bash"
	ln -s "$(command -v cat)" "$bin/cat"
	status=0
	(cd / && PATH="$bin" "$repo/scripts/hooks/stop-gate.sh" \
		<<<'{"stop_hook_active": false}' >"$scratch/out" 2>"$scratch/err") || status=$?
	err="$(cat "$scratch/err")"
	expect_status 2
	expect_err "jq not found"
	expect_calls 0
}

an_unexpected_failure_blocks_the_stop() {
	new_repo
	# A file named target makes mkdir fail after the gate ran green.
	touch "$repo/target"
	run_hook "$repo" false
	expect_status 2
	expect_err "failed unexpectedly"
}

tests=(
	gate_green_lets_the_agent_stop
	gate_red_blocks_the_stop
	unchanged_files_skip_the_gate
	a_repeated_red_stop_is_let_through
	a_new_stop_after_a_red_one_runs_the_gate
	a_repeated_red_stop_after_a_change_runs_the_gate
	a_green_run_after_a_red_one_clears_the_red_marker
	the_gate_runs_without_colors
	a_changed_rust_file_runs_the_gate_again
	a_renamed_rust_file_runs_the_gate_again
	a_deleted_tracked_file_runs_the_gate_again
	a_change_to_another_file_skips_the_gate
	a_linked_worktree_is_gated_in_its_own_tree
	a_missing_jq_blocks_the_stop
	an_unexpected_failure_blocks_the_stop
)

command -v jq >/dev/null 2>&1 || {
	echo "test.sh: jq not found; install jq to run these tests" >&2
	exit 1
}

failed=0
for t in "${tests[@]}"; do
	# A subshell with errexit, so the first failing check ends the test. Bash
	# ignores errexit inside an if condition, so the status is read afterwards.
	set +e
	(
		set -e
		"$t"
	) >"$scratch/log" 2>&1
	rc=$?
	set -e
	if ((rc == 0)); then
		echo "PASS $t"
	else
		echo "FAIL $t"
		sed 's/^/  /' "$scratch/log"
		failed=$((failed + 1))
	fi
done

if ((failed > 0)); then
	echo "test.sh: $failed of ${#tests[@]} tests failed"
	exit 1
fi
echo "test.sh: all ${#tests[@]} tests passed"
