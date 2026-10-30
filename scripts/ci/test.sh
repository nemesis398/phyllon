#!/usr/bin/env bash
# Tests for the two pull request checks CI runs, check-pr-title.sh and
# check-signoff.sh, and for scripts/github-settings.sh. The title tests call the
# script with a title; the sign-off tests build a git repository in a temporary
# directory, make commits with explicit identities and run the script inside
# it, with PR_AUTHOR and GITHUB_ACTIONS set as the test says. The settings tests
# put a stub gh first on PATH that answers from fixture JSON, so they never
# reach GitHub. Run it with:
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
settings_script="$ci_dir/../github-settings.sh"

# Keep the user's git configuration (signing, hooks, templates) out of the
# temporary repositories.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# CI sets these for the job; each test sets its own.
unset PR_AUTHOR GITHUB_ACTIONS

scratch="$(mktemp -d -p "${TMPDIR:-/tmp}" phyllon-ci-tests.XXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT

# Set by the run_* helpers for the test that is running.
repo=""
status=0
out=""
# The pull request's author and whether the check runs in CI, for run_signoff.
pr_author=""
in_ci=""

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

# Runs the sign-off check inside $repo for $1..$2, as a pull request by
# $pr_author, in CI if $in_ci is true.
run_signoff() {
	status=0
	out="$(cd "$repo" && PR_AUTHOR="$pr_author" GITHUB_ACTIONS="$in_ci" \
		"$signoff_check" "$1" "$2" 2>&1)" || status=$?
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

a_bot_commit_in_a_bot_pull_request_passes() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "$bot_name" "$bot_email" "build(deps): bump axum from 0.8.4 to 0.8.5" ""
	pr_author="$bot_name" in_ci=true
	run_signoff "$base" "$(rev HEAD)"
	expect_status 0
}

# Anyone can write Dependabot's identity into a commit; only GitHub decides
# who opened the pull request.
a_forged_bot_commit_in_a_human_pull_request_fails() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "$bot_name" "$bot_email" "build(deps): bump axum from 0.8.4 to 0.8.5" ""
	pr_author=nemesis398 in_ci=true
	run_signoff "$base" "$(rev HEAD)"
	expect_status 1
	expect_out "$(rev HEAD)"
}

a_bot_commit_without_a_pull_request_author_fails() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "$bot_name" "$bot_email" "build(deps): bump axum from 0.8.4 to 0.8.5" ""
	run_signoff "$base" "$(rev HEAD)"
	expect_status 1
}

a_human_commit_in_a_bot_pull_request_needs_a_signoff() {
	new_repo
	local base bot human
	base="$(rev HEAD)"
	commit_as "$bot_name" "$bot_email" "build(deps): bump axum from 0.8.4 to 0.8.5" ""
	bot="$(rev HEAD)"
	commit_as "Ada Lovelace" ada@example.com "fix: adapt to axum 0.8.5" ""
	human="$(rev HEAD)"
	pr_author="$bot_name" in_ci=true
	run_signoff "$base" "$human"
	expect_status 1
	expect_out "$human"
	expect_no_out "$bot"
}

# Only Dependabot's own identity is exempt, not anyone who takes its name.
the_dependabot_name_with_another_email_fails() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "$bot_name" someone@example.com "feat: one" ""
	pr_author="$bot_name" in_ci=true
	run_signoff "$base" "$(rev HEAD)"
	expect_status 1
}

# In CI a missing author would silently drop the exemption check's input.
a_missing_pull_request_author_in_ci_fails() {
	new_repo
	local base
	base="$(rev HEAD)"
	commit_as "Ada Lovelace" ada@example.com "feat: one" \
		"Signed-off-by: Ada Lovelace <ada@example.com>"
	in_ci=true
	run_signoff "$base" "$(rev HEAD)"
	expect_status 2
	expect_out "PR_AUTHOR"
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

# A pull request always has a commit, so an empty range means a wrong BASE.
an_empty_range_fails() {
	new_repo
	run_signoff "$(rev HEAD)" "$(rev HEAD)"
	expect_status 1
	expect_out "no commits"
}

an_unknown_base_fails() {
	new_repo
	run_signoff 0000000000000000000000000000000000000000 "$(rev HEAD)"
	expect_status 2
	expect_out "not a commit"
}

# Repository settings. The stub gh answers `gh api [-X METHOD] [-H HEADER]...
# repos/nemesis398/phyllon/PATH` from $fixtures/NAME.json, where NAME is PATH
# with / turned into _ ("repo" for the repository itself). A missing file
# answers 404 the way gh does, an empty one 204. Every call is logged to
# $fixtures/calls. A write fails unless GH_STUB_WRITES is set, and
# GH_STUB_FAIL=NAME makes a request to NAME, read or write, fail with HTTP 500.
mkdir "$scratch/bin"
cat >"$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == api ]] || { echo "stub gh: only api" >&2; exit 3; }
shift
method=GET path="" input=""
while (($#)); do
	case "$1" in
	-X | --method) method="$2"; shift 2 ;;
	-H | --header) shift 2 ;;
	--input) input="$2"; shift 2 ;;
	repos/*) path="$1"; shift ;;
	*) echo "stub gh: unexpected argument $1" >&2; exit 3 ;;
	esac
done
echo "$method $path" >>"$GH_FIXTURES/calls"
name="${path#repos/nemesis398/phyllon}" name="${name%%\?*}" name="${name#/}"
name="${name//\//_}" name="${name:-repo}"
if [[ "$method" != GET && -z "${GH_STUB_WRITES:-}" ]]; then
	echo "stub gh: $method $path" >&2
	exit 3
fi
if [[ "${GH_STUB_FAIL:-}" == "$name" ]]; then
	echo "gh: Server Error (HTTP 500)" >&2
	exit 1
fi
if [[ "$method" != GET ]]; then
	[[ "$input" != - ]] || cat >"$GH_FIXTURES/body-$name"
	exit 0
fi
if [[ ! -f "$GH_FIXTURES/$name.json" ]]; then
	echo '{"message":"Not Found","status":"404"}'
	echo "gh: Not Found (HTTP 404)" >&2
	exit 1
fi
cat "$GH_FIXTURES/$name.json"
STUB
chmod +x "$scratch/bin/gh"

# The answers of a repository whose every setting matches, shaped like
# GitHub's (API version 2026-03-10), extra fields included.
pristine="$scratch/pristine"
mkdir "$pristine"
cat >"$pristine/repo.json" <<'JSON'
{"id": 1, "full_name": "nemesis398/phyllon", "private": false,
 "description": "Self-hosted task library, worksheet engine and checker that AI clients use over MCP",
 "homepage": "https://phyllon.de", "has_issues": true, "has_discussions": true,
 "allow_squash_merge": true, "allow_merge_commit": false, "allow_rebase_merge": false,
 "allow_auto_merge": false, "squash_merge_commit_title": "PR_TITLE",
 "squash_merge_commit_message": "COMMIT_MESSAGES", "delete_branch_on_merge": true,
 "security_and_analysis": {"secret_scanning": {"status": "enabled"},
  "secret_scanning_push_protection": {"status": "enabled"},
  "dependabot_security_updates": {"status": "enabled"},
  "secret_scanning_validity_checks": {"status": "disabled"}}}
JSON
echo '{"names": ["edtech", "education", "llm", "math", "mcp", "mcp-server",
 "model-context-protocol", "pgvector", "postgresql", "rust", "self-hosted",
 "typst", "worksheet-generator", "worksheets"]}' >"$pristine/topics.json"
echo '{"enabled": true}' >"$pristine/private-vulnerability-reporting.json"
: >"$pristine/vulnerability-alerts.json"
echo '{"enabled": true, "paused": false}' >"$pristine/automated-security-fixes.json"
echo '{"state": "configured", "languages": ["actions", "python", "rust"],
 "query_suite": "default", "schedule": "weekly"}' >"$pristine/code-scanning_default-setup.json"
echo '{"enabled": true, "enforced_by_owner": false}' >"$pristine/immutable-releases.json"
echo '{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": false}' \
	>"$pristine/actions_permissions_workflow.json"
echo '{"approval_policy": "all_external_contributors"}' \
	>"$pristine/actions_permissions_fork-pr-contributor-approval.json"
echo '[{"id": 42, "name": "main", "target": "branch", "source_type": "Repository",
 "enforcement": "active"}]' >"$pristine/rulesets.json"
cat >"$pristine/rulesets_42.json" <<'JSON'
{"id": 42, "name": "main", "target": "branch", "source_type": "Repository",
 "source": "nemesis398/phyllon", "enforcement": "active", "bypass_actors": [],
 "current_user_can_bypass": "never",
 "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
 "rules": [{"type": "deletion"}, {"type": "non_fast_forward"},
  {"type": "required_linear_history"}, {"type": "required_signatures"},
  {"type": "pull_request", "parameters": {"required_approving_review_count": 0,
   "dismiss_stale_reviews_on_push": false, "require_code_owner_review": false,
   "require_extra_approval_for_unattributed_changes": true,
   "require_last_push_approval": false, "required_review_thread_resolution": false,
   "allowed_merge_methods": ["squash"], "required_reviewers": []}},
  {"type": "required_status_checks", "parameters": {
   "strict_required_status_checks_policy": false, "do_not_enforce_on_create": false,
   "required_status_checks": [{"context": "scripts", "integration_id": 15368},
    {"context": "gate", "integration_id": 15368}, {"context": "pr-title", "integration_id": 15368},
    {"context": "integration (17)", "integration_id": 15368},
    {"context": "integration (18)", "integration_id": 15368},
    {"context": "sign-off", "integration_id": 15368}, {"context": "markdown", "integration_id": 15368},
    {"context": "dependency-review", "integration_id": 15368}]}}]}
JSON

# The fixtures of the running test.
fixtures=""

new_fixtures() {
	fixtures="$(mktemp -d -p "$scratch")"
	cp -- "$pristine"/* "$fixtures"
}

# Rewrites fixture $1 with the jq filter $2.
edit_fixture() {
	jq "$2" "$fixtures/$1.json" >"$fixtures/tmp.json"
	mv -- "$fixtures/tmp.json" "$fixtures/$1.json"
}

run_settings() {
	status=0
	out="$(PATH="$scratch/bin:$PATH" GH_FIXTURES="$fixtures" \
		"$settings_script" "$@" 2>&1)" || status=$?
}

# Expects the audit to fail and to list $1.
expect_drift() {
	run_settings audit
	expect_status 1
	expect_out "$1"
}

the_audit_passes_when_every_setting_matches_and_only_reads() {
	new_fixtures
	run_settings audit
	expect_status 0
	expect_no_out "drift"
	if command grep -v '^GET ' "$fixtures/calls"; then
		echo "  the audit sent a write"
		return 1
	fi
}

repository_flags_that_differ_fail() {
	new_fixtures
	edit_fixture repo '.has_discussions = false | .allow_rebase_merge = true | .homepage = null'
	edit_fixture topics '.names -= ["rust"]'
	expect_drift "drift: repo .has_discussions: is false, want true"
	expect_out "drift: repo .allow_rebase_merge: is true, want false"
	expect_out 'drift: repo .homepage: is null, want "https://phyllon.de"'
	expect_out 'drift: topics .names: missing ["rust"], extra []'
	expect_out "audit: 4 settings differ"
}

security_settings_that_differ_fail() {
	new_fixtures
	edit_fixture repo '.security_and_analysis.secret_scanning_push_protection.status = "disabled"'
	edit_fixture automated-security-fixes '.enabled = false'
	edit_fixture code-scanning_default-setup '.state = "not-configured"'
	expect_drift 'drift: repo .security_and_analysis.secret_scanning_push_protection.status: is "disabled", want "enabled"'
	expect_out "drift: automated-security-fixes .enabled: is false, want true"
	expect_out 'drift: code-scanning/default-setup .state: is "not-configured", want "configured"'
}

# Dependabot pauses its security updates when its pull requests go ignored.
paused_security_updates_fail() {
	new_fixtures
	edit_fixture automated-security-fixes '.paused = true'
	expect_drift "drift: automated-security-fixes .paused: is true, want false"
}

# These endpoints answer 404 when the feature is off.
a_feature_that_answers_404_is_off() {
	new_fixtures
	rm -- "$fixtures/vulnerability-alerts.json" "$fixtures/immutable-releases.json"
	expect_drift "drift: vulnerability-alerts .enabled: is false, want true"
	expect_out "drift: immutable-releases .enabled: is false, want true"
}

actions_permissions_that_differ_fail() {
	new_fixtures
	edit_fixture actions_permissions_workflow \
		'.default_workflow_permissions = "write" | .can_approve_pull_request_reviews = true'
	edit_fixture actions_permissions_fork-pr-contributor-approval \
		'.approval_policy = "first_time_contributors"'
	expect_drift 'drift: actions/permissions/workflow .default_workflow_permissions: is "write", want "read"'
	expect_out "drift: actions/permissions/workflow .can_approve_pull_request_reviews: is true, want false"
	expect_out "drift: actions/permissions/fork-pr-contributor-approval .approval_policy"
}

a_missing_ruleset_fails() {
	new_fixtures
	echo '[]' >"$fixtures/rulesets.json"
	expect_drift "drift: ruleset main: missing"
}

a_second_ruleset_fails() {
	new_fixtures
	edit_fixture rulesets '. + [{"id": 43, "name": "tags", "target": "tag", "source_type": "Repository"}]'
	expect_drift "drift: ruleset tags: not in the table"
}

an_extra_rule_and_a_missing_rule_fail() {
	new_fixtures
	edit_fixture rulesets_42 '.rules += [{"type": "creation"}] |
		del(.rules[] | select(.type == "required_signatures"))'
	expect_drift "drift: ruleset main: extra rule creation"
	expect_out "drift: ruleset main: missing rule required_signatures"
}

parameters_that_differ_fail() {
	new_fixtures
	edit_fixture rulesets_42 '.enforcement = "disabled" |
		(.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count) = 1'
	expect_drift 'drift: ruleset main .enforcement: is "disabled", want "active"'
	expect_out "drift: ruleset main rule pull_request .required_approving_review_count: is 1, want 0"
}

# An extra parameter GitHub returns may be off, but not on.
an_extra_rule_parameter_that_is_on_fails() {
	new_fixtures
	edit_fixture rulesets_42 '(.rules[] | select(.type == "pull_request") | .parameters.required_reviewers) =
		[{"file_patterns": ["*"], "minimum_approvals": 1, "reviewer": {"id": 7, "type": "Team"}}]'
	expect_drift "drift: ruleset main rule pull_request .required_reviewers"
}

a_missing_check_and_a_check_from_another_app_fail() {
	new_fixtures
	edit_fixture rulesets_42 '(.rules[] | select(.type == "required_status_checks") |
		.parameters.required_status_checks) |= (map(select(.context != "scripts")) |
		map(if .context == "gate" then .integration_id = 1 end))'
	expect_drift 'drift: ruleset main rule required_status_checks .required_status_checks: missing [{"context":"gate","integration_id":15368},{"context":"scripts","integration_id":15368}], extra [{"context":"gate","integration_id":1}]'
}

a_bypass_actor_fails() {
	new_fixtures
	edit_fixture rulesets_42 \
		'.bypass_actors = [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]'
	expect_drift "drift: ruleset main: bypass actor RepositoryRole 5 (always)"
}

# A request that fails for another reason is an error, not drift.
a_failed_request_stops_the_audit() {
	new_fixtures
	GH_STUB_FAIL=actions_permissions_workflow run_settings audit
	expect_status 2
	expect_out "HTTP 500"
	expect_no_out "drift"
}

an_unknown_command_fails() {
	new_fixtures
	run_settings bogus
	expect_status 2
	expect_out "usage"
}

apply_writes_every_setting_and_updates_the_ruleset() {
	new_fixtures
	GH_STUB_WRITES=1 run_settings apply
	expect_status 0
	local p=repos/nemesis398/phyllon
	out="$(command grep -v '^GET ' "$fixtures/calls")"
	[[ "$out" == "PATCH $p
PUT $p/topics
PUT $p/private-vulnerability-reporting
PUT $p/vulnerability-alerts
PUT $p/automated-security-fixes
PUT $p/immutable-releases
PATCH $p/code-scanning/default-setup
PUT $p/actions/permissions/workflow
PUT $p/actions/permissions/fork-pr-contributor-approval
PUT $p/rulesets/42" ]] || {
		echo "  unexpected writes: $out"
		return 1
	}
	jq -e '.name == "main" and .bypass_actors == [] and (.rules | length) == 6' \
		"$fixtures/body-rulesets_42" >/dev/null
	jq -e '.homepage == "https://phyllon.de"' "$fixtures/body-repo" >/dev/null
}

# A failed write stops apply, so nothing after it runs on a half-set repository.
a_failed_write_stops_apply() {
	new_fixtures
	GH_STUB_WRITES=1 GH_STUB_FAIL=topics run_settings apply
	expect_status 2
	expect_out "PUT repos/nemesis398/phyllon/topics failed"
	out="$(command grep -v '^GET ' "$fixtures/calls")"
	[[ "$out" == $'PATCH repos/nemesis398/phyllon\nPUT repos/nemesis398/phyllon/topics' ]] || {
		echo "  unexpected writes: $out"
		return 1
	}
}

# Without the list, apply cannot know whether the ruleset exists, and a POST
# could create a second one. It stops before it writes anything.
an_unreadable_ruleset_list_stops_apply() {
	new_fixtures
	rm -- "$fixtures/rulesets.json"
	GH_STUB_WRITES=1 run_settings apply
	expect_status 2
	expect_out "rulesets"
	if command grep -v '^GET ' "$fixtures/calls"; then
		echo "  apply wrote without the ruleset list"
		return 1
	fi
}

apply_creates_a_missing_ruleset() {
	new_fixtures
	echo '[]' >"$fixtures/rulesets.json"
	GH_STUB_WRITES=1 run_settings apply
	expect_status 0
	out="$(<"$fixtures/calls")"
	expect_out "POST repos/nemesis398/phyllon/rulesets"
	expect_no_out "PUT repos/nemesis398/phyllon/rulesets"
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
	a_bot_commit_in_a_bot_pull_request_passes
	a_forged_bot_commit_in_a_human_pull_request_fails
	a_bot_commit_without_a_pull_request_author_fails
	a_human_commit_in_a_bot_pull_request_needs_a_signoff
	the_dependabot_name_with_another_email_fails
	a_missing_pull_request_author_in_ci_fails
	a_merge_commit_is_skipped_and_its_commits_are_checked
	a_signed_branch_with_an_unsigned_merge_passes
	an_empty_range_fails
	an_unknown_base_fails
	the_audit_passes_when_every_setting_matches_and_only_reads
	repository_flags_that_differ_fail
	security_settings_that_differ_fail
	paused_security_updates_fail
	a_feature_that_answers_404_is_off
	actions_permissions_that_differ_fail
	a_missing_ruleset_fails
	a_second_ruleset_fails
	an_extra_rule_and_a_missing_rule_fail
	parameters_that_differ_fail
	an_extra_rule_parameter_that_is_on_fails
	a_missing_check_and_a_check_from_another_app_fail
	a_bypass_actor_fails
	a_failed_request_stops_the_audit
	an_unknown_command_fails
	apply_writes_every_setting_and_updates_the_ruleset
	apply_creates_a_missing_ruleset
	a_failed_write_stops_apply
	an_unreadable_ruleset_list_stops_apply
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
