#!/usr/bin/env bash
# Tests for the two pull request checks CI runs: check-pr-title.sh and
# check-signoff.sh. The title tests call the script with a title; the sign-off
# tests build a git repository in a temporary directory, make commits with
# explicit identities and run the script inside it. Run it with:
#
#   scripts/ci/test.sh
#
# It prints PASS or FAIL per test and exits non-zero if any test failed.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail

ci_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
title_check="$ci_dir/check-pr-title.sh"
signoff_check="$ci_dir/check-signoff.sh"

# Keep the user's git configuration (signing, hooks, templates) out of the
# temporary repositories.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

scratch="$(mktemp -d -p "${TMPDIR:-/tmp}" phyllon-ci-tests.XXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT

# Set by the run_* helpers for the test that is running.
repo=""
status=0
out=""

# The identity Dependabot commits with.
bot_name='dependabot[bot]'
bot_email='49699333+dependabot[bot]@users.noreply.github.com'

run_title() {
	status=0
	out="$("$title_check" "$1" 2>&1)" || status=$?
}

# Creates a repository with one commit, which the sign-off tests use as BASE.
new_repo() {
	repo="$(mktemp -d -p "$scratch")"
	git init -q -b main "$repo"
	commit_as "Ada Lovelace" ada@example.com "base" ""
}

# Makes a commit in $repo with author and committer $1 <$2>, subject $3 and
# the message body $4 (may be empty), and prints nothing.
commit_as() {
	local name="$1" email="$2" subject="$3" body="$4" message
	message="$subject"
	[[ -z "$body" ]] || message+=$'\n\n'"$body"
	GIT_AUTHOR_NAME="$name" GIT_AUTHOR_EMAIL="$email" \
		GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" \
		git -C "$repo" commit -q --allow-empty -m "$message"
}

# Runs the sign-off check inside $repo for $1..$2.
run_signoff() {
	status=0
	out="$(cd "$repo" && "$signoff_check" "$1" "$2" 2>&1)" || status=$?
}

rev() {
	git -C "$repo" rev-parse "$1"
}

# Each check prints why it failed and returns non-zero, which fails the test.
expect_status() {
	[[ "$status" == "$1" ]] || {
		echo "  expected exit $1, got $status; output: $out"
		return 1
	}
}
expect_out() {
	[[ "$out" == *"$1"* ]] || {
		echo "  expected the output to contain '$1', got: $out"
		return 1
	}
}
expect_no_out() {
	[[ "$out" != *"$1"* ]] || {
		echo "  expected the output not to contain '$1', got: $out"
		return 1
	}
}

# Titles.

a_title_with_a_scope_passes() {
	run_title 'feat(web): add the shell'
	expect_status 0
}

a_dependabot_cargo_title_passes() {
	run_title 'build(deps): bump axum from 0.8.4 to 0.8.5'
	expect_status 0
}

# The shapes .github/dependabot.yml produces for the other ecosystems: actions
# pinned by SHA name the version from the trailing comment.
a_dependabot_actions_title_passes() {
	run_title 'ci(deps): bump actions/checkout from 7.0.1 to 7.1.0'
	expect_status 0
}

a_dependabot_toolchain_title_passes() {
	run_title 'build(deps): bump rust from 1.99.1 to 1.100.0'
	expect_status 0
}

a_breaking_change_title_passes() {
	run_title 'feat(api)!: drop the old endpoint'
	expect_status 0
}

a_title_without_a_type_fails() {
	run_title 'Update stuff'
	expect_status 1
}

a_title_without_a_summary_fails() {
	run_title 'feat:'
	expect_status 1
}

an_unknown_type_fails() {
	run_title 'feature: add the shell'
	expect_status 1
}

a_title_of_72_characters_passes() {
	local title
	title="docs: $(printf 'a%.0s' {1..66})"
	((${#title} == 72))
	run_title "$title"
	expect_status 0
}

a_title_of_73_characters_fails() {
	local title
	title="docs: $(printf 'a%.0s' {1..67})"
	((${#title} == 73))
	run_title "$title"
	expect_status 1
	expect_out "73 characters"
}

# Umlauts take two bytes each in UTF-8; the limit counts characters.
a_title_of_72_characters_with_umlauts_passes() {
	local title
	title="docs: credit Mika Böhme $(printf 'ä%.0s' {1..48})"
	run_title "$title"
	expect_status 0
	[[ "$(printf '%s' "$title" | wc -c)" -gt 72 ]] || {
		echo "  the test title should be longer than 72 bytes"
		return 1
	}
}

a_title_of_73_characters_with_umlauts_fails() {
	run_title "docs: credit Mika Böhme $(printf 'ä%.0s' {1..49})"
	expect_status 1
	expect_out "73 characters"
}

a_title_with_a_newline_fails() {
	run_title $'feat: add the shell\nand more'
	expect_status 1
}

# Sign-offs.

a_matching_signoff_passes() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "Ada Lovelace" ada@example.com "feat: one" \
		"Signed-off-by: Ada Lovelace <ada@example.com>"
	run_signoff "$base" "$(rev HEAD)"
	expect_status 0
}

a_missing_signoff_fails_and_names_the_commit() {
	new_repo
	local base good bad
	base="$(rev HEAD)"
	commit_as "Ada Lovelace" ada@example.com "feat: one" \
		"Signed-off-by: Ada Lovelace <ada@example.com>"
	good="$(rev HEAD)"
	commit_as "Ada Lovelace" ada@example.com "feat: two" ""
	bad="$(rev HEAD)"
	run_signoff "$base" "$bad"
	expect_status 1
	expect_out "$bad"
	expect_no_out "$good"
}

a_signoff_for_another_person_fails() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "Ada Lovelace" ada@example.com "feat: one" \
		"Signed-off-by: Charles Babbage <charles@example.com>"
	run_signoff "$base" "$(rev HEAD)"
	expect_status 1
	expect_out "$(rev HEAD)"
}

a_signoff_with_another_email_fails() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "Ada Lovelace" ada@example.com "feat: one" \
		"Signed-off-by: Ada Lovelace <ada@example.org>"
	run_signoff "$base" "$(rev HEAD)"
	expect_status 1
}

a_matching_signoff_among_several_passes() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "Ada Lovelace" ada@example.com "feat: one" \
		"Signed-off-by: Charles Babbage <charles@example.com>
Signed-off-by: Ada Lovelace <ada@example.com>"
	run_signoff "$base" "$(rev HEAD)"
	expect_status 0
}

# A sign-off line in the middle of the body is not a trailer.
a_signoff_outside_the_trailers_fails() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "Ada Lovelace" ada@example.com "feat: one" \
		"Signed-off-by: Ada Lovelace <ada@example.com>

More text after it."
	run_signoff "$base" "$(rev HEAD)"
	expect_status 1
}

a_dependabot_commit_passes_without_a_signoff() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "$bot_name" "$bot_email" "build(deps): bump axum from 0.8.4 to 0.8.5" ""
	run_signoff "$base" "$(rev HEAD)"
	expect_status 0
}

# Only Dependabot's own identity is exempt, not anyone who takes its name.
the_dependabot_name_with_another_email_fails() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "$bot_name" someone@example.com "feat: one" ""
	run_signoff "$base" "$(rev HEAD)"
	expect_status 1
}

# A merge commit is skipped, but the commits it brings in are checked.
a_merge_commit_is_skipped_and_its_commits_are_checked() {
	new_repo
	local base side
	base="$(rev HEAD)"
	git -C "$repo" switch -q -c side
	commit_as "Ada Lovelace" ada@example.com "feat: side" ""
	side="$(rev HEAD)"
	git -C "$repo" switch -q main
	commit_as "Ada Lovelace" ada@example.com "feat: main" \
		"Signed-off-by: Ada Lovelace <ada@example.com>"
	GIT_AUTHOR_NAME="Ada Lovelace" GIT_AUTHOR_EMAIL=ada@example.com \
		GIT_COMMITTER_NAME="Ada Lovelace" GIT_COMMITTER_EMAIL=ada@example.com \
		git -C "$repo" merge -q --no-ff -m "Merge branch side" side
	run_signoff "$base" "$(rev HEAD)"
	expect_status 1
	expect_out "$side"
	expect_no_out "$(rev HEAD)"
}

a_signed_branch_with_an_unsigned_merge_passes() {
	new_repo
	local base
	base="$(rev HEAD)"
	git -C "$repo" switch -q -c side
	commit_as "Ada Lovelace" ada@example.com "feat: side" \
		"Signed-off-by: Ada Lovelace <ada@example.com>"
	git -C "$repo" switch -q main
	commit_as "Ada Lovelace" ada@example.com "feat: main" \
		"Signed-off-by: Ada Lovelace <ada@example.com>"
	GIT_AUTHOR_NAME="Ada Lovelace" GIT_AUTHOR_EMAIL=ada@example.com \
		GIT_COMMITTER_NAME="Ada Lovelace" GIT_COMMITTER_EMAIL=ada@example.com \
		git -C "$repo" merge -q --no-ff -m "Merge branch side" side
	run_signoff "$base" "$(rev HEAD)"
	expect_status 0
}

an_unknown_base_fails() {
	new_repo
	run_signoff 0000000000000000000000000000000000000000 "$(rev HEAD)"
	expect_status 2
	expect_out "not a commit"
}

tests=(
	a_title_with_a_scope_passes
	a_dependabot_cargo_title_passes
	a_dependabot_actions_title_passes
	a_dependabot_toolchain_title_passes
	a_breaking_change_title_passes
	a_title_without_a_type_fails
	a_title_without_a_summary_fails
	an_unknown_type_fails
	a_title_of_72_characters_passes
	a_title_of_73_characters_fails
	a_title_of_72_characters_with_umlauts_passes
	a_title_of_73_characters_with_umlauts_fails
	a_title_with_a_newline_fails
	a_matching_signoff_passes
	a_missing_signoff_fails_and_names_the_commit
	a_signoff_for_another_person_fails
	a_signoff_with_another_email_fails
	a_matching_signoff_among_several_passes
	a_signoff_outside_the_trailers_fails
	a_dependabot_commit_passes_without_a_signoff
	the_dependabot_name_with_another_email_fails
	a_merge_commit_is_skipped_and_its_commits_are_checked
	a_signed_branch_with_an_unsigned_merge_passes
	an_unknown_base_fails
)

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
