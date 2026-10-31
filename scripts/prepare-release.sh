#!/usr/bin/env bash
# Prepares a release pull request on the maintainer's machine, because a pull
# request that the workflow's own token opens starts no CI. Run it on a clean,
# current main:
#
#   scripts/prepare-release.sh [--dry-run] [--co-author 'NAME <EMAIL>'] [VERSION]
#
# It fetches the tags, raises the version and writes the changelog with
# release-plz, formats the changelog as CI expects, cuts release-plz-v<version>
# and commits "chore(release): v<version>" with the sign-off from user.name
# and user.email. --co-author adds a Co-Authored-By trailer, for an agent that
# runs it. It never pushes: push the branch yourself, then open the pull
# request. Merging it is the decision to release, and release.yml then tags,
# builds, verifies and publishes.
#
# Without VERSION, release-plz picks the version from the conventional
# commits; the first release is 0.1.0. With VERSION, that version is taken.
# --dry-run does everything up to the commit, prints the branch, the version
# and the changelog entry, then puts the files back and leaves main as it was.
#
# A release that opens a new minor line, such as 0.2.0, also moves the line
# the stack names (0.1 today) in compose.yaml, deploy/quadlet/phyllon.container,
# scripts/quadlet-test.sh and the scan-image job of
# .github/workflows/nightly.yml. Nothing else prompts it, and the nightly scan
# keeps scanning the old line.
#
# One release branch at a time, cut from current main: branches stacked on
# each other conflict in Cargo.toml, Cargo.lock and CHANGELOG.md once the
# earlier ones are squash-merged (docs/decisions/0006-release-pipeline.md).
#
# It exits 0 when the branch is ready (or the dry run is done), 1 on a failed
# check and 2 on a usage error. Needs git, cargo, jq, release-plz and the npm
# tools from `npm ci --ignore-scripts`.

set -euo pipefail

crate=phyllon
remote=origin
# The changes release-plz may make. Anything else stops the script.
files=(Cargo.toml Cargo.lock CHANGELOG.md)

usage() {
	printf 'prepare-release.sh: %s\n' "$@" >&2
	printf "usage: prepare-release.sh [--dry-run] [--co-author 'NAME <EMAIL>'] [VERSION]\n" >&2
	exit 2
}

fail() {
	printf 'prepare-release.sh: %s\n' "$@" >&2
	exit 1
}

dry_run=false
co_author=
version=
while (($# > 0)); do
	case "$1" in
	--dry-run) dry_run=true ;;
	--co-author)
		(($# >= 2)) || usage "--co-author needs a value"
		[[ "$2" =~ ^[^\<\>]+\ \<[^\<\>[:space:]]+@[^\<\>[:space:]]+\>$ ]] ||
			usage "--co-author takes 'NAME <EMAIL>', not '$2'"
		co_author="$2"
		shift
		;;
	-*) usage "unknown option $1" ;;
	*)
		[[ -z "$version" ]] || usage "only one VERSION"
		# release.yml accepts only a plain X.Y.Z tag, so no pre-release suffix.
		[[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
			usage "VERSION must look like 0.1.0, not '$1'"
		version="$1"
		;;
	esac
	shift
done

for tool in git cargo jq release-plz npx; do
	command -v "$tool" >/dev/null 2>&1 || fail "$tool not found"
done

cd "$(git rev-parse --show-toplevel)"

[[ -x node_modules/.bin/prettier && -x node_modules/.bin/markdownlint-cli2 ]] ||
	fail "prettier and markdownlint-cli2 are missing; run: npm ci --ignore-scripts"
[[ "$(git branch --show-current)" == main ]] || fail "check out main first"
[[ -z "$(git status --porcelain)" ]] ||
	fail "the working tree is not clean; commit or stash first"

# Without the tags, release-plz update sees no earlier release and changes
# nothing. --prune drops release branches that were merged and deleted, and
# together with --tags it also deletes local tags the remote lacks, on
# purpose: release-plz must see exactly the published tags.
git fetch --prune --tags "$remote"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "refs/remotes/$remote/main")" ]] ||
	fail "main is not at $remote/main; pull or reset it first"
open="$(git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/$remote/release-plz-*")"
[[ -z "$open" ]] || fail "a release branch is still open: $open"

# The tree was clean, so from here on every change is this script's. Put the
# files back unless the commit was made.
had_changelog=false
[[ -e CHANGELOG.md ]] && had_changelog=true
committed=false
switched=false
restore() {
	"$committed" && return
	git restore --staged --worktree -- Cargo.toml Cargo.lock
	if "$had_changelog"; then
		git restore --staged --worktree -- CHANGELOG.md
	else
		rm -f -- CHANGELOG.md
	fi
	# A failed commit, such as one the pre-commit hook stopped, leaves main
	# checked out and no release branch.
	if "$switched"; then
		git switch --quiet main
		git branch --quiet --delete --force -- "$branch"
	fi
}
trap restore EXIT

crate_version() {
	cargo metadata --no-deps --format-version 1 --offline |
		jq -r --arg crate "$crate" '.packages[] | select(.name == $crate) | .version'
}

before="$(crate_version)"
tags="$(git tag --list 'v[0-9]*')"
if ! "$had_changelog"; then
	# The first release. release-plz update takes the version in Cargo.toml as
	# the initial release and writes CHANGELOG.md for it, and set-version fails
	# without a changelog, so the version is set by hand.
	[[ -z "$tags" ]] || fail "CHANGELOG.md is missing, but release tags exist"
	version="${version:-0.1.0}"
	sed -i "0,/^version = \".*\"\$/s//version = \"$version\"/" Cargo.toml
	cargo update --workspace --offline
	release-plz update --allow-dirty
else
	[[ -n "$tags" ]] || fail "CHANGELOG.md exists, but no release tag does"
	# update first, which adds the new entry, then set-version, which renames
	# the newest entry. Alone, set-version would rename the last release's.
	release-plz update
	after_update="$(crate_version)"
	[[ "$after_update" != "$before" ]] ||
		fail "release-plz found nothing to release since v$before"
	if [[ -n "$version" ]]; then
		[[ "$(printf '%s\n' "$before" "$version" | sort -V | tail -n 1)" == "$version" &&
			"$version" != "$before" ]] ||
			fail "VERSION $version is not above the current $before"
		release-plz set-version "$crate@$version"
	fi
	cargo update --workspace --offline
fi

new="$(crate_version)"
# release.yml releases only a plain X.Y.Z, also when release-plz picked it.
[[ "$new" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
	fail "release-plz chose $new, which is not a plain X.Y.Z version"
[[ -z "$version" || "$new" == "$version" ]] ||
	fail "Cargo.toml says $new, not $version"
tag="v$new"
branch="release-plz-$tag"
! git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null ||
	fail "the tag $tag exists already"
! git rev-parse --quiet --verify "refs/heads/$branch" >/dev/null ||
	fail "the branch $branch exists already; delete it first"
cargo metadata --format-version 1 --offline --locked >/dev/null ||
	fail "Cargo.lock does not match Cargo.toml"

# CI checks every Markdown file with prettier and markdownlint-cli2.
npx --no-install prettier --log-level warn --write CHANGELOG.md
npx --no-install markdownlint-cli2 CHANGELOG.md >/dev/null ||
	fail "CHANGELOG.md fails markdownlint-cli2; run it to see why"

changed="$(git status --porcelain --untracked-files=all | cut -c4- | sort)"
expected="$(printf '%s\n' "${files[@]}" | sort)"
[[ "$changed" == "$expected" ]] ||
	fail "expected changes in ${files[*]}, found:" "$changed"
grep -qxF "## [Unreleased]" CHANGELOG.md || fail "CHANGELOG.md has no Unreleased heading"

printf 'branch:  %s\n' "$branch"
printf 'version: %s -> %s\n' "$before" "$new"
printf '\n'
git --no-pager diff -- Cargo.toml
printf '\nchangelog entry:\n\n'
awk -v head="## [$new]" '
	index($0, head) == 1 { on = 1; print; next }
	on && /^## \[/ { exit }
	on { print }
' CHANGELOG.md

if "$dry_run"; then
	printf '\nprepare-release.sh: dry run, so no branch and no commit; the files are back as they were.\n'
	exit 0
fi

trailers=()
[[ -z "$co_author" ]] || trailers=(--trailer "Co-Authored-By: $co_author")
git switch --create "$branch"
switched=true
git add -- "${files[@]}"
git commit --signoff "${trailers[@]}" --message "chore(release): $tag"
committed=true

printf '\nprepare-release.sh: %s is ready. Push it and open the pull request:\n' "$branch"
printf '  git push --set-upstream %s %s\n' "$remote" "$branch"
