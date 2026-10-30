#!/usr/bin/env bash
# Checks the Developer Certificate of Origin sign-off of every commit in
# BASE..HEAD of the repository in the working directory: each needs a
# Signed-off-by trailer equal to "<author name> <author email>". CI's sign-off
# job runs it with the pull request's base branch and head commit, and with
# PR_AUTHOR set to the login of the pull request's author. Run it with:
#
#   scripts/ci/check-signoff.sh origin/main HEAD
#
# Commits by Dependabot are exempt, because a bot cannot certify anything. A
# commit's author name and email are whatever its maker wrote, so the
# exemption also needs the pull request to be Dependabot's: PR_AUTHOR, which
# GitHub sets from the account that opened it, must be dependabot[bot]. A
# human's commit in a Dependabot pull request still needs its sign-off.
# Without PR_AUTHOR nothing is exempt, and in CI (GITHUB_ACTIONS=true) a
# missing PR_AUTHOR is an error.
#
# Merge commits are skipped. GitHub's "Update branch" button makes one without
# a sign-off, and the squash merge drops it from main; the commits it brings in
# from the pull request's side are checked on their own, and those from the
# base are already on main.
#
# It prints each failing commit and exits 0 when every commit passes, 1 when
# one does not or the range is empty, and 2 on a usage error.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail

# Dependabot's login and commit identity.
bot_login='dependabot[bot]'
bot='dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>'

usage() {
	printf 'check-signoff.sh: %s\n' "$@" >&2
	exit 2
}

(($# == 2)) || usage "usage: check-signoff.sh BASE HEAD"
base="$1"
head="$2"
for ref in "$base" "$head"; do
	git rev-parse --quiet --verify "$ref^{commit}" >/dev/null ||
		usage "$ref is not a commit in this repository." \
			"In CI the checkout needs fetch-depth: 0 to see the whole range."
done
pr_author="${PR_AUTHOR:-}"
if [[ -z "$pr_author" && "${GITHUB_ACTIONS:-}" == true ]]; then
	usage "PR_AUTHOR is not set. The workflow passes the pull request's author" \
		"(github.event.pull_request.user.login) through env."
fi

# A pull request has at least one commit, so an empty range means a wrong BASE
# or HEAD, not a pass.
if [[ -z "$(git rev-list -n 1 "$base..$head")" ]]; then
	echo "check-signoff.sh: there are no commits in $base..$head; check BASE and HEAD."
	exit 1
fi

commits=()
mapfile -t commits < <(git rev-list --no-merges --reverse "$base..$head")

failed=0
for sha in "${commits[@]}"; do
	author="$(git log -1 --format='%an <%ae>' "$sha")"
	[[ "$author" == "$bot" && "$pr_author" == "$bot_login" ]] && continue
	# Only the trailer block at the end of the message counts, as for git
	# interpret-trailers; unfold joins a value folded over several lines.
	signoffs=()
	mapfile -t signoffs < <(git log -1 \
		--format='%(trailers:key=Signed-off-by,valueonly,unfold)' "$sha")
	found=false
	for signoff in "${signoffs[@]}"; do
		[[ "$signoff" != "$author" ]] || found=true
	done
	if [[ "$found" == false ]]; then
		printf 'FAIL %s %s\n' "$sha" "$(git log -1 --format=%s "$sha")"
		printf '  expected: Signed-off-by: %s\n' "$author"
		for signoff in "${signoffs[@]}"; do
			[[ -z "$signoff" ]] || printf '  found:    Signed-off-by: %s\n' "$signoff"
		done
		failed=$((failed + 1))
	fi
done

if ((failed > 0)); then
	echo "check-signoff.sh: $failed of ${#commits[@]} commits lack a sign-off that" \
		"matches their author. Add it with 'git commit --amend -s' or" \
		"'git rebase --signoff $base', then force-push."
	exit 1
fi
echo "check-signoff.sh: all ${#commits[@]} commits in $base..$head are signed off"
