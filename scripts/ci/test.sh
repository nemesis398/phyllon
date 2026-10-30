#!/usr/bin/env bash
# Tests for the two pull request checks CI runs, check-pr-title.sh and
# check-signoff.sh, for the skill link check check-skill-links.sh, for
# scripts/github-settings.sh and scripts/posture.sh, and for the image checks
# and the cloud-init seed of scripts/ci/fedora-vm.sh. The title tests call the
# script with a title; the sign-off tests build a git repository in a
# temporary directory, make commits with explicit identities and run the
# script inside it, with PR_AUTHOR and GITHUB_ACTIONS set as the test says.
# The link tests build a tree of skills and links in a temporary directory and
# check it. The settings tests put a stub gh first on PATH that answers from
# fixture JSON, so they never reach GitHub, and the posture tests do the same
# with a stub container engine. The tests of scripts/ci/fedora-vm.sh's trust
# chain and seed run it with stub gpgv, curl, cloud-localds and QEMU, so they
# need neither the network nor KVM. Run it with:
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
links_check="$ci_dir/check-skill-links.sh"

# Keep the user's git configuration (signing, hooks, templates) out of the
# temporary repositories.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# CI sets these for the job; each test sets its own.
unset PR_AUTHOR GITHUB_ACTIONS

scratch="$(mktemp -d -p "${TMPDIR:-/tmp}" phyllon-ci-tests.XXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT

# Set by the run_* helpers for the test that is running.
repo=""
# The tree of the running link test.
tree=""
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

# Skill links. Each test builds a tree with .agents/skills/ and
# .claude/skills/ in a temporary directory and runs check-skill-links.sh on it.

# Creates an empty tree for the link tests in $tree.
new_tree() {
	tree="$(mktemp -d -p "$scratch")"
	mkdir -p "$tree/.agents/skills" "$tree/.claude/skills"
}

# Adds the skill $1, a directory with a SKILL.md, to $tree.
add_skill() {
	mkdir "$tree/.agents/skills/$1"
	printf -- '---\nname: %s\n---\n' "$1" >"$tree/.agents/skills/$1/SKILL.md"
}

# Links .claude/skills/$1 to $2, by default the relative path to skill $1.
link_skill() {
	ln -s -- "${2:-../../.agents/skills/$1}" "$tree/.claude/skills/$1"
}

run_links() {
	status=0
	out="$("$links_check" "$tree" 2>&1)" || status=$?
}

a_resolving_link_passes() {
	new_tree
	add_skill conscience
	link_skill conscience
	run_links
	expect_status 0
	expect_out "1 skill"
}

a_dangling_link_fails_and_names_it() {
	new_tree
	add_skill conscience
	link_skill conscience
	link_skill gone
	run_links
	expect_status 1
	expect_out ".claude/skills/gone"
	expect_no_out ".claude/skills/conscience"
}

# Every failure is reported, not only the first.
a_skill_without_a_link_fails_and_names_it() {
	new_tree
	add_skill conscience
	add_skill review
	add_skill commits
	link_skill conscience
	run_links
	expect_status 1
	expect_out ".agents/skills/review"
	expect_out ".agents/skills/commits"
	expect_no_out ".agents/skills/conscience"
}

# A copy in .claude/skills/ would drift from the shipped skill.
a_copy_instead_of_a_link_fails() {
	new_tree
	add_skill conscience
	cp -r -- "$tree/.agents/skills/conscience" "$tree/.claude/skills/conscience"
	run_links
	expect_status 1
	expect_out ".claude/skills/conscience"
	expect_out "not a symlink"
}

a_file_among_the_links_fails() {
	new_tree
	add_skill conscience
	link_skill conscience
	echo notes >"$tree/.claude/skills/README.md"
	run_links
	expect_status 1
	expect_out ".claude/skills/README.md"
}

# An absolute link resolves only on the machine that made it.
an_absolute_link_fails() {
	new_tree
	add_skill conscience
	link_skill conscience "$tree/.agents/skills/conscience"
	run_links
	expect_status 1
	expect_out ".claude/skills/conscience"
	expect_out "absolute"
}

# A link to a directory with a SKILL.md outside .agents/skills/ still fails.
a_link_outside_the_skills_fails() {
	new_tree
	add_skill conscience
	link_skill conscience
	mkdir "$tree/docs"
	cp -- "$tree/.agents/skills/conscience/SKILL.md" "$tree/docs/SKILL.md"
	link_skill stray ../../docs
	run_links
	expect_status 1
	expect_out ".claude/skills/stray"
}

# The link's name is the skill's name, so it must match the directory.
a_link_to_another_skill_fails() {
	new_tree
	add_skill conscience
	add_skill review
	link_skill conscience
	link_skill review
	link_skill critic ../../.agents/skills/review
	run_links
	expect_status 1
	expect_out ".claude/skills/critic"
}

a_skill_without_a_skill_md_fails() {
	new_tree
	add_skill conscience
	link_skill conscience
	mkdir "$tree/.agents/skills/draft"
	link_skill draft
	run_links
	expect_status 1
	expect_out ".agents/skills/draft"
	expect_out "SKILL.md"
}

# A skill that is itself a symlink would ship whatever it points to.
a_symlinked_skill_fails() {
	new_tree
	add_skill conscience
	link_skill conscience
	mkdir -p "$tree/elsewhere/review"
	echo '---' >"$tree/elsewhere/review/SKILL.md"
	ln -s -- ../../elsewhere/review "$tree/.agents/skills/review"
	link_skill review
	run_links
	expect_status 1
	expect_out ".agents/skills/review: is a symlink"
}

a_file_among_the_skills_fails() {
	new_tree
	add_skill conscience
	link_skill conscience
	echo notes >"$tree/.agents/skills/README.md"
	run_links
	expect_status 1
	expect_out ".agents/skills/README.md: is not a directory"
}

# A SKILL.md that is a symlink would ship whatever it points to.
a_symlinked_skill_md_fails() {
	new_tree
	add_skill conscience
	link_skill conscience
	echo '---' >"$tree/outside.md"
	rm -- "$tree/.agents/skills/conscience/SKILL.md"
	ln -s -- ../../../outside.md "$tree/.agents/skills/conscience/SKILL.md"
	run_links
	expect_status 1
	expect_out ".agents/skills/conscience/SKILL.md: is a symlink"
}

# A symlinked .agents would ship a tree from outside the repository.
a_symlinked_agents_directory_fails() {
	new_tree
	rm -r -- "$tree/.agents"
	mkdir -p "$tree/elsewhere/skills/conscience"
	echo '---' >"$tree/elsewhere/skills/conscience/SKILL.md"
	ln -s -- elsewhere "$tree/.agents"
	link_skill conscience
	run_links
	expect_status 1
	expect_out ".agents/skills: resolves outside the repository"
}

a_symlinked_link_directory_fails() {
	new_tree
	add_skill conscience
	rm -r -- "$tree/.claude/skills"
	mkdir "$tree/elsewhere"
	ln -s -- ../.agents/skills/conscience "$tree/elsewhere/conscience"
	ln -s -- ../elsewhere "$tree/.claude/skills"
	run_links
	expect_status 1
	expect_out ".claude/skills: resolves outside the repository"
}

# Each link points straight at its skill. A chain through a second link, here
# one with an absolute target, resolves only on the machine that made it.
a_chain_through_an_absolute_link_fails() {
	new_tree
	add_skill conscience
	ln -s -- "$tree/.agents/skills/conscience" "$tree/hop"
	link_skill conscience ../../hop
	run_links
	expect_status 1
	expect_out ".claude/skills/conscience: links to ../../hop, not to the skill"
}

a_name_with_spaces_is_checked() {
	new_tree
	add_skill "two words"
	link_skill "two words"
	add_skill "no link"
	run_links
	expect_status 1
	expect_out ".agents/skills/no link"
	expect_no_out ".agents/skills/two words"
}

# No skills at all means a wrong root or a deleted directory, not a pass.
an_empty_skill_directory_fails() {
	new_tree
	run_links
	expect_status 1
	expect_out "no skills"
}

a_missing_skill_directory_fails() {
	new_tree
	rm -r -- "$tree/.agents"
	run_links
	expect_status 1
	expect_out ".agents/skills"
}

a_missing_link_directory_fails_for_each_skill() {
	new_tree
	add_skill conscience
	rm -r -- "$tree/.claude"
	run_links
	expect_status 1
	expect_out ".agents/skills/conscience"
}

# Without an argument the script checks the repository it lives in, from any
# working directory.
without_an_argument_it_checks_its_own_tree() {
	new_tree
	add_skill conscience
	link_skill conscience
	mkdir -p "$tree/scripts/ci"
	cp -- "$links_check" "$tree/scripts/ci/"
	status=0
	out="$(cd / && "$tree/scripts/ci/check-skill-links.sh" 2>&1)" || status=$?
	expect_status 0
	rm -- "$tree/.claude/skills/conscience"
	status=0
	out="$(cd / && "$tree/scripts/ci/check-skill-links.sh" 2>&1)" || status=$?
	expect_status 1
	expect_out ".agents/skills/conscience"
}

a_root_that_is_not_a_directory_is_a_usage_error() {
	tree="$scratch/nowhere"
	run_links
	expect_status 2
}

# An empty argument is a mistake, not a request for the default root.
an_empty_root_is_a_usage_error() {
	tree=""
	run_links
	expect_status 2
	expect_out "ROOT is empty"
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
    {"context": "dependency-review", "integration_id": 15368},
    {"context": "stack-docker", "integration_id": 15368},
    {"context": "browser", "integration_id": 15368}]}}]}
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

# Container posture. The stub engine, linked as docker and as podman, answers
# `ps` with the Ids of $POSTURE_FIXTURE when the filter names the project
# phyllon-stack-test (or with $POSTURE_IDS when set), and `inspect` with the
# whole file. The fixtures are real
# inspect output of the stack, cut to the fields posture.sh reads: Docker
# writes CapDrop as given and the Name with a slash, Podman expands CapDrop to
# the dropped capabilities and lists what is left in BoundingCaps.
cat >"$scratch/bin/engine" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
ps)
	[[ " $* " == *" label=com.docker.compose.project=phyllon-stack-test "* ]] || exit 0
	if [[ -n "${POSTURE_IDS:-}" ]]; then echo "$POSTURE_IDS"; exit 0; fi
	jq -r '.[].Id' "$POSTURE_FIXTURE"
	;;
inspect) cat "$POSTURE_FIXTURE" ;;
*) echo "stub engine: unexpected $*" >&2; exit 3 ;;
esac
STUB
chmod +x "$scratch/bin/engine"
ln -s engine "$scratch/bin/docker"
ln -s engine "$scratch/bin/podman"
posture_script="$ci_dir/../posture.sh"

cat >"$scratch/posture-docker.json" <<'JSON'
[{"Id": "a1", "Name": "/phyllon-stack-test-proxy-1",
  "Config": {"User": "65533:65533", "Labels": {"com.docker.compose.service": "proxy"},
   "Healthcheck": {"Test": ["CMD", "wget", "-qO", "/dev/null", "http://127.0.0.1:2019/config/"]}},
  "HostConfig": {"Privileged": false, "PidMode": "", "IpcMode": "private",
   "PublishAllPorts": false, "NetworkMode": "phyllon-stack-test_edge",
   "CapAdd": ["CAP_NET_BIND_SERVICE"], "CapDrop": ["ALL"], "SecurityOpt": ["no-new-privileges:true"],
   "Memory": 268435456, "PidsLimit": 128, "ReadonlyRootfs": true,
   "PortBindings": {"8080/tcp": [{"HostIp": "", "HostPort": "8080"}],
    "8443/tcp": [{"HostIp": "", "HostPort": "8443"}]}},
  "Mounts": [{"Type": "bind", "Source": "/w/deploy/Caddyfile", "Destination": "/etc/caddy/Caddyfile"}]},
 {"Id": "b2", "Name": "/phyllon-stack-test-phyllon-1",
  "Config": {"User": "65532:65532", "Labels": {"com.docker.compose.service": "phyllon"},
   "Healthcheck": {"Test": ["CMD", "/usr/local/bin/phyllon", "healthcheck"]}},
  "HostConfig": {"Privileged": false, "PidMode": "", "IpcMode": "private",
   "PublishAllPorts": false, "NetworkMode": "phyllon-stack-test_edge",
   "CapAdd": null, "CapDrop": ["ALL"], "SecurityOpt": ["no-new-privileges:true"],
   "Memory": 536870912, "PidsLimit": 256, "ReadonlyRootfs": true, "PortBindings": {}},
  "Mounts": [{"Type": "bind", "Source": "/w/secrets/db_runtime_password",
   "Destination": "/run/secrets/db_runtime_password"}]},
 {"Id": "c3", "Name": "/phyllon-stack-test-db-1",
  "Config": {"User": "999:999", "Labels": {"com.docker.compose.service": "db"},
   "Healthcheck": {"Test": ["CMD", "pg_isready", "-h", "127.0.0.1", "-d", "phyllon"]}},
  "HostConfig": {"Privileged": false, "PidMode": "", "IpcMode": "private",
   "PublishAllPorts": false, "NetworkMode": "phyllon-stack-test_db",
   "CapAdd": null, "CapDrop": ["ALL"], "SecurityOpt": ["no-new-privileges:true"],
   "Memory": 1073741824, "PidsLimit": 256, "ReadonlyRootfs": true, "PortBindings": {}},
  "Mounts": [{"Type": "volume", "Source": "/var/lib/docker/volumes/phyllon-stack-test_db-data/_data",
   "Destination": "/var/lib/postgresql"}]}]
JSON
cat >"$scratch/posture-podman.json" <<'JSON'
[{"Id": "60214719ca3b", "Name": "phyllon-stack-test-proxy-1",
  "Config": {"User": "65533:65533", "Labels": {"com.docker.compose.service": "proxy"},
   "Healthcheck": {"Test": ["CMD", "wget", "-qO", "/dev/null", "http://127.0.0.1:2019/config/"]}},
  "HostConfig": {"Privileged": false, "PidMode": "private", "IpcMode": "shareable",
   "PublishAllPorts": false, "NetworkMode": "bridge", "CapAdd": [],
   "CapDrop": ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_FOWNER", "CAP_FSETID", "CAP_KILL",
    "CAP_SETFCAP", "CAP_SETGID", "CAP_SETPCAP", "CAP_SETUID", "CAP_SYS_CHROOT"],
   "SecurityOpt": ["no-new-privileges"], "Memory": 268435456, "PidsLimit": 128,
   "ReadonlyRootfs": true, "PortBindings": {"8080/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8080"}],
    "8443/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8443"}]}},
  "EffectiveCaps": ["CAP_NET_BIND_SERVICE"], "BoundingCaps": ["CAP_NET_BIND_SERVICE"],
  "Mounts": [{"Type": "bind", "Source": "/w/deploy/Caddyfile", "Destination": "/etc/caddy/Caddyfile"}]},
 {"Id": "013789400cc5", "Name": "phyllon-stack-test-phyllon-1",
  "Config": {"User": "65532:65532", "Labels": {"com.docker.compose.service": "phyllon"},
   "Healthcheck": {"Test": ["CMD", "/usr/local/bin/phyllon", "healthcheck"]}},
  "HostConfig": {"Privileged": false, "PidMode": "private", "IpcMode": "shareable",
   "PublishAllPorts": false, "NetworkMode": "bridge", "CapAdd": [],
   "CapDrop": ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_FOWNER", "CAP_FSETID", "CAP_KILL",
    "CAP_NET_BIND_SERVICE", "CAP_SETFCAP", "CAP_SETGID", "CAP_SETPCAP", "CAP_SETUID", "CAP_SYS_CHROOT"],
   "SecurityOpt": ["no-new-privileges"], "Memory": 536870912, "PidsLimit": 256,
   "ReadonlyRootfs": true, "PortBindings": {}},
  "EffectiveCaps": null, "BoundingCaps": null,
  "Mounts": [{"Type": "bind", "Source": "/w/deploy/phyllon.toml", "Destination": "/etc/phyllon/phyllon.toml"}]},
 {"Id": "9693f3b7e546", "Name": "phyllon-stack-test-db-1",
  "Config": {"User": "999:999", "Labels": {"com.docker.compose.service": "db"},
   "Healthcheck": {"Test": ["CMD", "pg_isready", "-h", "127.0.0.1", "-d", "phyllon"]}},
  "HostConfig": {"Privileged": false, "PidMode": "private", "IpcMode": "shareable",
   "PublishAllPorts": false, "NetworkMode": "bridge", "CapAdd": [],
   "CapDrop": ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_FOWNER", "CAP_FSETID", "CAP_KILL",
    "CAP_NET_BIND_SERVICE", "CAP_SETFCAP", "CAP_SETGID", "CAP_SETPCAP", "CAP_SETUID", "CAP_SYS_CHROOT"],
   "SecurityOpt": ["no-new-privileges"], "Memory": 1073741824, "PidsLimit": 256,
   "ReadonlyRootfs": true, "PortBindings": {}},
  "EffectiveCaps": null, "BoundingCaps": null,
  "Mounts": [{"Type": "volume", "Source": "/v/phyllon-stack-test_db-data/_data", "Destination": "/var/lib/postgresql"}]}]
JSON

# The fixture of the running posture test.
posture_fixture=""

# Copies the fixture of engine $1 for the test to edit.
new_posture() {
	posture_fixture="$(mktemp -p "$scratch")"
	cp -- "$scratch/posture-$1.json" "$posture_fixture"
}

# Rewrites the container of service $1 with the jq filter given last; the
# arguments between are passed to jq, such as --arg NAME VALUE.
edit_container() {
	local service="$1" filter="${*: -1}"
	jq --arg s "$service" "${@:2:$#-2}" \
		"map(if .Config.Labels[\"com.docker.compose.service\"] == \$s then $filter else . end)" \
		"$posture_fixture" >"$scratch/posture-tmp.json"
	mv -- "$scratch/posture-tmp.json" "$posture_fixture"
}

run_posture() {
	status=0
	out="$(PATH="$scratch/bin:$PATH" POSTURE_FIXTURE="$posture_fixture" \
		"$posture_script" "$1" phyllon-stack-test 2>&1)" || status=$?
}

# Expects posture.sh under docker to fail and to name the gap $1.
expect_gap() {
	run_posture docker
	expect_status 1
	expect_out "$1"
}

a_compliant_docker_stack_passes() {
	new_posture docker
	run_posture docker
	expect_status 0
	expect_out "posture: 42 checks passed on 3 containers"
}

a_compliant_podman_stack_passes() {
	new_posture podman
	run_posture podman
	expect_status 0
	expect_out "posture: 42 checks passed on 3 containers"
}

a_project_without_containers_fails() {
	new_posture docker
	echo '[]' >"$posture_fixture"
	run_posture docker
	expect_status 1
	expect_out "no containers"
}

an_unknown_engine_is_refused() {
	new_posture docker
	run_posture nerdctl
	expect_status 2
	expect_out "usage"
}

a_privileged_container_fails() {
	new_posture docker
	edit_container phyllon '.HostConfig.Privileged = true'
	expect_gap "phyllon-stack-test-phyllon-1: runs privileged"
	expect_out "posture: 1 gap, 41 of 42 checks passed"
}

the_host_network_fails() {
	new_posture docker
	edit_container db '.HostConfig.NetworkMode = "host"'
	expect_gap "phyllon-stack-test-db-1: uses the host network"
}

capdrop_without_all_fails() {
	new_posture docker
	edit_container db '.HostConfig.CapDrop = ["NET_RAW"]'
	expect_gap "phyllon-stack-test-db-1: does not drop all capabilities"
}

an_added_capability_fails() {
	new_posture docker
	edit_container phyllon '.HostConfig.CapAdd = ["SYS_ADMIN"]'
	expect_gap "phyllon-stack-test-phyllon-1: keeps the capabilities SYS_ADMIN"
}

a_capability_left_under_podman_fails() {
	new_posture podman
	edit_container db '.BoundingCaps = ["CAP_NET_RAW"] | .EffectiveCaps = ["CAP_NET_RAW"]'
	run_posture podman
	expect_status 1
	expect_out "phyllon-stack-test-db-1: keeps the capabilities NET_RAW"
}

a_missing_no_new_privileges_fails() {
	new_posture docker
	edit_container proxy '.HostConfig.SecurityOpt = ["label=disable"]'
	expect_gap "phyllon-stack-test-proxy-1: does not set no-new-privileges"
}

a_missing_memory_limit_fails() {
	new_posture docker
	edit_container db '.HostConfig.Memory = 0'
	expect_gap "phyllon-stack-test-db-1: has no memory limit"
}

a_missing_pids_limit_fails() {
	new_posture docker
	edit_container db '.HostConfig.PidsLimit = null'
	expect_gap "phyllon-stack-test-db-1: has no pids limit"
}

a_missing_healthcheck_fails() {
	new_posture docker
	edit_container proxy 'del(.Config.Healthcheck)'
	edit_container db '.Config.Healthcheck.Test = ["NONE"]'
	expect_gap "phyllon-stack-test-proxy-1: has no healthcheck"
	expect_out "phyllon-stack-test-db-1: has no healthcheck"
}

an_engine_socket_mount_fails() {
	new_posture docker
	edit_container proxy '.Mounts += [{"Type": "bind", "Source": "/var/run/docker.sock",
		"Destination": "/var/run/docker.sock"}]'
	edit_container db '.Mounts += [{"Type": "bind", "Source": "/run/user/1000/podman/podman.sock",
		"Destination": "/engine"}]'
	expect_gap "phyllon-stack-test-proxy-1: mounts an engine socket or its directory: /var/run/docker.sock"
	expect_out "phyllon-stack-test-db-1: mounts an engine socket or its directory: /run/user/1000/podman/podman.sock"
}

# A directory that holds an engine socket gives the same access.
an_engine_socket_directory_mount_fails() {
	local dir
	for dir in /run /var/run/ /run/user /run/user/ /run/user/1000/podman /run/podman /run/docker \
		/run/containerd/containerd.sock; do
		new_posture docker
		# shellcheck disable=SC2016 # $d is a jq variable
		edit_container db --arg d "$dir" '.Mounts += [{"Type": "bind", "Source": $d, "Destination": "/host"}]'
		expect_gap "phyllon-stack-test-db-1: mounts an engine socket or its directory: $dir"
	done
}

a_root_user_fails() {
	new_posture docker
	edit_container phyllon '.Config.User = ""'
	edit_container db '.Config.User = "0:999"'
	edit_container proxy '.Config.User = "root"'
	expect_gap 'phyllon-stack-test-phyllon-1: runs as root (user "")'
	expect_out 'phyllon-stack-test-db-1: runs as root (user "0:999")'
	expect_out 'phyllon-stack-test-proxy-1: runs as root (user "root")'
}

a_published_port_outside_the_proxy_fails() {
	new_posture docker
	edit_container db '.HostConfig.PortBindings = {"5432/tcp": [{"HostIp": "", "HostPort": "5432"}]}'
	expect_gap "phyllon-stack-test-db-1: publishes a port, which only proxy may"
}

a_published_port_through_publish_all_fails() {
	new_posture docker
	edit_container phyllon '.HostConfig.PublishAllPorts = true'
	expect_gap "phyllon-stack-test-phyllon-1: publishes a port, which only proxy may"
}

a_writable_root_fails() {
	new_posture docker
	edit_container phyllon '.HostConfig.ReadonlyRootfs = false'
	edit_container db 'del(.HostConfig.ReadonlyRootfs)'
	edit_container proxy '.HostConfig.ReadonlyRootfs = false'
	expect_gap "phyllon-stack-test-phyllon-1: has a writable root filesystem"
	expect_out "phyllon-stack-test-db-1: has a writable root filesystem"
	expect_out "phyllon-stack-test-proxy-1: has a writable root filesystem"
}

a_shared_network_namespace_fails() {
	new_posture docker
	edit_container phyllon '.HostConfig.NetworkMode = "container:c3"'
	edit_container db '.HostConfig.NetworkMode = "service:phyllon"'
	expect_gap "phyllon-stack-test-phyllon-1: shares the network of another container"
	expect_out "phyllon-stack-test-db-1: shares the network of another container"
}

the_host_pid_and_ipc_namespaces_fail() {
	new_posture podman
	edit_container db '.HostConfig.PidMode = "host" | .HostConfig.IpcMode = "host"'
	run_posture podman
	expect_status 1
	expect_out "phyllon-stack-test-db-1: uses the host pid namespace"
	expect_out "phyllon-stack-test-db-1: uses the host ipc namespace"
}

# Malformed inspect output is an error (exit 2), not a gap and not jq's own
# exit code.
# ps found containers, so an inspect answer without any is an error, not a
# pass on zero checks.
an_empty_inspect_answer_is_an_error() {
	new_posture docker
	echo '[]' >"$posture_fixture"
	POSTURE_IDS=x1 run_posture docker
	expect_status 2
	expect_out "no containers in the inspect output"
}

malformed_inspect_output_is_an_error() {
	new_posture docker
	edit_container db '.Mounts[0].Source = 5'
	run_posture docker
	expect_status 2
	expect_out "cannot read"
	echo 'not json' >"$posture_fixture"
	POSTURE_IDS=x1 run_posture docker
	expect_status 2
	expect_out "cannot read"
	echo '{"Id": "x1"}' >"$posture_fixture"
	POSTURE_IDS=x1 run_posture docker
	expect_status 2
}

# The Fedora VM's trust chain. fedora-vm.sh runs with stubs first on PATH:
# gpgv writes $FVM_STATUS to its status fd and $FVM_TEXT as the signed text
# and exits $FVM_GPGV_EXIT; curl copies the file the URL names from
# $FVM_FIXTURES; qemu-img and cloud-localds create their output file, and
# cloud-localds keeps a copy of the user-data as $FVM_USERDATA; and
# qemu-system-x86_64 lists the run directory and exits 1. Each stub logs its
# call to $FVM_LOG. The real script, with its pinned fingerprint, decides.
vm_script="$ci_dir/fedora-vm.sh"
vm_release="$(sed -n 's/^release=//p' "$vm_script")"
vm_compose="$(sed -n 's/^compose=//p' "$vm_script")"
vm_pinned="$(sed -n 's/^key_fingerprint=//p' "$vm_script")"
vm_image="Fedora-Cloud-Base-Generic-$vm_release-$vm_compose.x86_64.qcow2"
vm_checksum="Fedora-Cloud-$vm_release-$vm_compose-x86_64-CHECKSUM"
vm_other=D6179C63D7986F1490F5026BEA672792C859988B
mkdir "$scratch/vmbin"
cat >"$scratch/vmbin/gpgv" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
fd="" output=""
while (($#)); do
	case "$1" in
	--keyring) shift 2 ;;
	--status-fd) fd="$2"; shift 2 ;;
	--output) output="$2"; shift 2 ;;
	--) shift; break ;;
	*) echo "stub gpgv: unexpected $1" >&2; exit 3 ;;
	esac
done
[[ -n "$fd" && -n "$output" && $# == 1 ]] || { echo "stub gpgv: bad call" >&2; exit 3; }
echo "gpgv $1" >>"$FVM_LOG"
cat -- "$FVM_STATUS" >&"$fd"
cp -- "$FVM_TEXT" "$output"
exit "${FVM_GPGV_EXIT:-0}"
STUB
cat >"$scratch/vmbin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "curl $*" >>"$FVM_LOG"
output=""
while (($#)); do
	case "$1" in
	--output) output="$2"; shift 2 ;;
	--) shift; break ;;
	*) shift ;;
	esac
done
[[ -n "$output" && $# == 1 ]] || { echo "stub curl: bad call" >&2; exit 3; }
[[ -f "$FVM_FIXTURES/${1##*/}" ]] || { echo "curl: (22) 404" >&2; exit 22; }
cp -- "$FVM_FIXTURES/${1##*/}" "$output"
STUB
cat >"$scratch/vmbin/qemu-img" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "qemu-img $*" >>"$FVM_LOG"
: >"${@: -2:1}"
STUB
cat >"$scratch/vmbin/cloud-localds" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "cloud-localds $*" >>"$FVM_LOG"
cp -- "$2" "$FVM_USERDATA"
: >"$1"
STUB
cat >"$scratch/vmbin/qemu-system-x86_64" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "qemu-system-x86_64 $*" >>"$FVM_LOG"
for arg in "$@"; do
	case "$arg" in
	*file=*/disk.qcow2,*)
		disk="${arg#*file=}" disk="${disk%%,*}"
		echo "run dir: $(cd "${disk%/disk.qcow2}" && ls -A | tr '\n' ' ')" >>"$FVM_LOG"
		;;
	esac
done
exit 1
STUB
chmod +x "$scratch/vmbin"/*

# The directory of the running VM test: fixtures/, the stub inputs and log,
# and the cache, which the script gets as the relative path "cache".
vm_dir=""
# The SHA-256 of the running test's image.
vm_sum=""

# Prints the VALIDSIG status line for signing key $1 with primary key $2.
validsig() {
	echo "[GNUPG:] VALIDSIG $1 2026-04-24 1777044852 0 4 0 1 8 01 $2"
}

# Sets up fixtures that pass: an image, the key bundle and CHECKSUM files
# (whose bytes the stub gpgv ignores), a good signature by the pinned key and
# a signed text listing the image's hash after another file's.
new_vm() {
	local sum
	vm_dir="$(mktemp -d -p "$scratch")"
	mkdir "$vm_dir/fixtures"
	head -c 4096 /dev/urandom >"$vm_dir/fixtures/$vm_image"
	echo key >"$vm_dir/fixtures/fedora.gpg"
	echo signed >"$vm_dir/fixtures/$vm_checksum"
	validsig "$vm_pinned" "$vm_pinned" >"$vm_dir/status"
	sum="$(sha256sum "$vm_dir/fixtures/$vm_image")"
	vm_sum="${sum%% *}"
	printf '%s\n' "# $vm_image: 4096 bytes" \
		"SHA256 (Fedora-Cloud-Base-AmazonEC2-$vm_release-$vm_compose.x86_64.raw.xz) = $(printf '%064d' 0)" \
		"SHA256 ($vm_image) = $vm_sum" >"$vm_dir/text"
}

# Runs fedora-vm.sh with the options given and the command true.
run_vm() {
	status=0
	: >"$vm_dir/log"
	rm -f -- "$vm_dir/user-data"
	out="$(cd "$vm_dir" && PATH="$scratch/vmbin:$PATH" FVM_LOG="$vm_dir/log" \
		FVM_FIXTURES="$vm_dir/fixtures" FVM_STATUS="$vm_dir/status" \
		FVM_TEXT="$vm_dir/text" FVM_USERDATA="$vm_dir/user-data" \
		PHYLLON_VM_CACHE=cache "$vm_script" "$@" -- true </dev/null 2>&1)" || status=$?
}

# Expects the run to have failed before QEMU and left no run directory.
expect_refused() {
	expect_status 1
	expect_out "$1"
	if command grep -q '^qemu-system-x86_64' "$vm_dir/log"; then
		echo "  QEMU ran"
		return 1
	fi
	if compgen -G "$vm_dir/cache/run.*" >/dev/null; then
		echo "  a run directory was left behind"
		return 1
	fi
}

# Expects that nothing unverified entered the cache.
expect_empty_cache() {
	local left
	left="$(cd "$vm_dir/cache" && ls -A)"
	[[ -z "$left" ]] || {
		echo "  the cache holds: $left"
		return 1
	}
}

a_signature_by_another_key_is_refused() {
	new_vm
	validsig "$vm_other" "$vm_other" >"$vm_dir/status"
	run_vm
	expect_refused "signed by '$vm_other', not by the pinned key $vm_pinned"
	expect_empty_cache
	if command grep -q "curl .*/$vm_image" "$vm_dir/log"; then
		echo "  the image was downloaded"
		return 1
	fi
}

# VALIDSIG names the signing key first and its primary key last; a subkey's
# fingerprint must not stand in for the primary.
a_pinned_signing_key_under_another_primary_is_refused() {
	new_vm
	validsig "$vm_pinned" "$vm_other" >"$vm_dir/status"
	run_vm
	expect_refused "not by the pinned key"
	expect_empty_cache
}

two_signatures_are_refused() {
	new_vm
	{
		validsig "$vm_pinned" "$vm_pinned"
		validsig "$vm_other" "$vm_other"
	} >"$vm_dir/status"
	run_vm
	expect_refused "not by the pinned key"
	expect_empty_cache
}

a_signature_without_validsig_is_refused() {
	new_vm
	echo "[GNUPG:] GOODSIG DBFCF71C6D9F90A6 Fedora (44)" >"$vm_dir/status"
	run_vm
	expect_refused "signed by 'nobody'"
	expect_empty_cache
}

a_failing_gpgv_is_refused() {
	new_vm
	FVM_GPGV_EXIT=1 run_vm
	expect_refused "does not verify"
	expect_empty_cache
}

an_image_with_another_hash_is_refused() {
	new_vm
	sed -i "s/= $vm_sum\$/= $(printf '%064d' 1)/" "$vm_dir/text"
	run_vm
	expect_refused "the downloaded image does not match the signed checksum"
	if [[ -e "$vm_dir/cache/$vm_image" ]]; then
		echo "  the image entered the cache"
		return 1
	fi
}

# Replaces the image's line in the signed text with the lines given.
vm_lines() {
	command grep -v "^SHA256 ($vm_image)" "$vm_dir/text" >"$vm_dir/text.new" || true
	printf '%s\n' "$@" >>"$vm_dir/text.new"
	mv -- "$vm_dir/text.new" "$vm_dir/text"
}

a_signed_text_without_the_image_is_refused() {
	new_vm
	vm_lines
	run_vm
	expect_refused "lists no single SHA-256 for $vm_image"
}

two_lines_for_the_image_are_refused() {
	new_vm
	vm_lines "SHA256 ($vm_image) = $vm_sum" "SHA256 ($vm_image) = $vm_sum"
	run_vm
	expect_refused "lists no single SHA-256"
}

a_malformed_hash_is_refused() {
	new_vm
	vm_lines "SHA256 ($vm_image) = ${vm_sum^^}"
	run_vm
	expect_refused "lists no single SHA-256"
	new_vm
	vm_lines "SHA256 ($vm_image) = ${vm_sum:1}"
	run_vm
	expect_refused "lists no single SHA-256"
	new_vm
	vm_lines "SHA256 ($vm_image) = $vm_sum trailing"
	run_vm
	expect_refused "lists no single SHA-256"
}

a_crlf_line_is_refused() {
	new_vm
	vm_lines "SHA256 ($vm_image) = $vm_sum"$'\r'
	run_vm
	expect_refused "lists no single SHA-256"
}

# The right hash under a name that only looks like the image's: a pattern
# that treats the dots as wildcards, or matches a prefix, would accept them.
a_near_miss_file_name_is_refused() {
	local name
	for name in "${vm_image//./X}" "$vm_image.xz" "x$vm_image" "${vm_image%.qcow2}"; do
		new_vm
		vm_lines "SHA256 ($name) = $vm_sum"
		run_vm
		expect_refused "lists no single SHA-256"
	done
}

# The image passes, enters the cache read-only, and the VM boots from an
# overlay on its absolute path. QEMU itself needs /dev/kvm; without access the
# run must stop there, after the checks.
a_verified_image_reaches_qemu() {
	new_vm
	run_vm
	expect_out "image verified: Fedora $vm_release ($vm_compose), signed by $vm_pinned"
	[[ -f "$vm_dir/cache/$vm_image" && ! -w "$vm_dir/cache/$vm_image" ]] || {
		echo "  the image is not in the cache, or is writable"
		return 1
	}
	command grep -q -- "^qemu-img create .* -b $vm_dir/cache/$vm_image " "$vm_dir/log" || {
		echo "  qemu-img did not get the absolute backing path:"
		cat "$vm_dir/log"
		return 1
	}
	command grep -q -- "^curl .*--speed-limit 1048576 --speed-time 30 .*/$vm_image\$" "$vm_dir/log" || {
		echo "  the image download has no stall limit:"
		command grep '^curl' "$vm_dir/log"
		return 1
	}
	if [[ -r /dev/kvm && -w /dev/kvm ]]; then
		expect_status 1
		expect_out "QEMU did not start"
		command grep -q -- '^qemu-system-x86_64 .*-enable-kvm' "$vm_dir/log" || {
			echo "  QEMU did not run"
			return 1
		}
		# The seed holds the host's private key; neither it nor the
		# user-data built from it may outlive the seed's creation.
		command grep -q '^run dir: .*seed\.img' "$vm_dir/log" || return 1
		if command grep -Eq '^run dir: (.* )?(user-data|host_ed25519) ' "$vm_dir/log"; then
			echo "  the host key or the user-data was left: $(command grep '^run dir' "$vm_dir/log")"
			return 1
		fi
	else
		expect_refused "/dev/kvm"
	fi
	if compgen -G "$vm_dir/cache/run.*" >/dev/null; then
		echo "  a run directory was left behind"
		return 1
	fi
}

# A cached image is checked again on every start, without a download.
a_cached_image_altered_later_is_refused() {
	new_vm
	run_vm
	chmod u+w "$vm_dir/cache/$vm_image"
	printf 'x' | dd of="$vm_dir/cache/$vm_image" bs=1 seek=100 conv=notrunc status=none
	run_vm
	expect_refused "the cached image does not match the signed checksum"
	if command grep -q '^curl' "$vm_dir/log"; then
		echo "  the warm start downloaded"
		return 1
	fi
}

# Root's work happens at boot, through cloud-init, so the VM user needs no
# sudo: --package installs a package and --linger keeps the user's systemd
# running without a login.
the_seed_installs_packages_and_turns_on_linger() {
	new_vm
	# Quoted, so YAML keeps a name such as null a string.
	run_vm --package docker-compose --package jq --package null --linger
	[[ -f "$vm_dir/user-data" ]] || {
		echo "  no seed was built: $out"
		return 1
	}
	local seed
	seed="$(<"$vm_dir/user-data")"
	[[ "$seed" == *$'\npackages:\n  - \'docker-compose\'\n  - \'jq\'\n  - \'null\'\n'* ]] || {
		echo "  the packages are not in the user-data, quoted:"
		cat "$vm_dir/user-data"
		return 1
	}
	[[ "$seed" == *$'\nruncmd:\n  - [loginctl, enable-linger, phyllon]'* ]] || {
		echo "  linger is not in the user-data:"
		cat "$vm_dir/user-data"
		return 1
	}
	if command grep -Eq '^ *(sudo|groups):' "$vm_dir/user-data"; then
		echo "  the user-data gives the user sudo or groups"
		return 1
	fi
}

# Without the options the seed is the one phase A tested: no packages and
# no commands as root.
the_seed_has_no_root_work_by_default() {
	new_vm
	run_vm
	[[ -f "$vm_dir/user-data" ]] || {
		echo "  no seed was built: $out"
		return 1
	}
	if command grep -Eq '^(packages|runcmd|bootcmd|write_files):' "$vm_dir/user-data"; then
		echo "  the default user-data does root work:"
		cat "$vm_dir/user-data"
		return 1
	fi
}

# A name goes into YAML that root acts on, so anything but a plain package
# name is refused before anything is downloaded or built.
a_package_name_that_is_not_plain_is_refused() {
	local name
	for name in "" "-y" "jq evil" $'jq\n  - evil' "jq]" "jq#x" "jq'" "../jq"; do
		new_vm
		run_vm --package "$name"
		expect_refused "is not a package name"
		if [[ -e "$vm_dir/user-data" ]] || command grep -q '^curl' "$vm_dir/log"; then
			echo "  the run went on after the name '$name'"
			return 1
		fi
	done
	# A missing name must not swallow the separator.
	new_vm
	run_vm --package
	expect_refused "'--' is not a package name"
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
	a_resolving_link_passes
	a_dangling_link_fails_and_names_it
	a_skill_without_a_link_fails_and_names_it
	a_copy_instead_of_a_link_fails
	a_file_among_the_links_fails
	an_absolute_link_fails
	a_link_outside_the_skills_fails
	a_link_to_another_skill_fails
	a_skill_without_a_skill_md_fails
	a_symlinked_skill_fails
	a_file_among_the_skills_fails
	a_symlinked_skill_md_fails
	a_symlinked_agents_directory_fails
	a_symlinked_link_directory_fails
	a_chain_through_an_absolute_link_fails
	a_name_with_spaces_is_checked
	an_empty_skill_directory_fails
	a_missing_skill_directory_fails
	a_missing_link_directory_fails_for_each_skill
	without_an_argument_it_checks_its_own_tree
	a_root_that_is_not_a_directory_is_a_usage_error
	an_empty_root_is_a_usage_error
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
	a_compliant_docker_stack_passes
	a_compliant_podman_stack_passes
	a_project_without_containers_fails
	an_unknown_engine_is_refused
	a_privileged_container_fails
	the_host_network_fails
	capdrop_without_all_fails
	an_added_capability_fails
	a_capability_left_under_podman_fails
	a_missing_no_new_privileges_fails
	a_missing_memory_limit_fails
	a_missing_pids_limit_fails
	a_missing_healthcheck_fails
	an_engine_socket_mount_fails
	an_engine_socket_directory_mount_fails
	a_root_user_fails
	a_published_port_outside_the_proxy_fails
	a_published_port_through_publish_all_fails
	a_writable_root_fails
	a_shared_network_namespace_fails
	the_host_pid_and_ipc_namespaces_fail
	an_empty_inspect_answer_is_an_error
	malformed_inspect_output_is_an_error
	a_signature_by_another_key_is_refused
	a_pinned_signing_key_under_another_primary_is_refused
	two_signatures_are_refused
	a_signature_without_validsig_is_refused
	a_failing_gpgv_is_refused
	an_image_with_another_hash_is_refused
	a_signed_text_without_the_image_is_refused
	two_lines_for_the_image_are_refused
	a_malformed_hash_is_refused
	a_crlf_line_is_refused
	a_near_miss_file_name_is_refused
	a_verified_image_reaches_qemu
	a_cached_image_altered_later_is_refused
	the_seed_installs_packages_and_turns_on_linger
	the_seed_has_no_root_work_by_default
	a_package_name_that_is_not_plain_is_refused
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
