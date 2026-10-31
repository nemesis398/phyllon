#!/usr/bin/env bash
# Checks that the copies of each image reference agree. Dependabot bumps the
# Caddy and pgvector digests in compose.yaml, but not in the Quadlet units or
# in ci.yml, and a new minor line of Phyllon has to be named in six files by
# hand, so a copy left behind would go unnoticed: CI replaces the Phyllon
# image and tests whatever the units name. It checks the tree ROOT, by default
# the repository this script lives in, from any working directory. CI's
# scripts job runs it. Run it with:
#
#   scripts/ci/check-image-pins.sh [ROOT]
#
# It reads exactly these lines, and no line in a comment:
#
# - Caddy: the "image: docker.io/library/caddy:TAG@DIGEST" line of
#   compose.yaml and the "Image=docker.io/library/caddy:TAG@DIGEST" line of
#   deploy/quadlet/phyllon-proxy.container.
# - pgvector: the "image: docker.io/pgvector/pgvector:TAG@DIGEST" line of
#   compose.yaml and the "Image=docker.io/pgvector/pgvector:TAG@DIGEST" line of
#   deploy/quadlet/phyllon-db.container. In .github/workflows/ci.yml, the
#   "image: pgvector/pgvector@DIGEST # TAG" line (or one that names the tag
#   before the digest) of the integration matrix entry whose "- postgres: N"
#   is the N of compose.yaml's tag, as in 0.8.7-pg18. The other entries have
#   no copy to agree with.
# - The Phyllon minor line, ghcr.io/nemesis398/phyllon:LINE: compose.yaml's
#   "image: ${PHYLLON_IMAGE:-...}", .env.example's "PHYLLON_IMAGE=...",
#   deploy/quadlet/phyllon.container's "Image=...", the "image: ..." input of
#   .github/workflows/nightly.yml's scan, the "podman tag localhost/phyllon:ci
#   ..." line of .github/workflows/podman.yml and scripts/quadlet-test.sh's
#   "image=...".
#
# It fails when a file is missing, when a file has none or more than one of
# its lines, when a Caddy or pgvector reference is not pinned by tag and
# sha256 digest, when a copy names another tag or digest than compose.yaml,
# and when the Phyllon line is not MAJOR.MINOR or differs from compose.yaml's.
# docs/install.md names the line in prose too; scripts/prepare-release.sh says
# to update it by hand.
#
# It prints each failure with the file and line it concerns and exits 0 when
# the copies agree, 1 when something fails, and 2 on a usage error.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail

usage() {
	printf 'check-image-pins.sh: %s\n' "$@" >&2
	exit 2
}

(($# <= 1)) || usage "usage: check-image-pins.sh [ROOT]"
# An empty argument is a mistake, not a request for the default.
(($# == 0)) || [[ -n "$1" ]] || usage "ROOT is empty; omit it to check this repository."
root="${1:-$(dirname "${BASH_SOURCE[0]}")/../..}"
[[ -d "$root" ]] || usage "$root is not a directory."
root="$(CDPATH='' cd -- "$root" && pwd -P)"

failures=()

# A tag and a sha256 digest, as in 2.11.7@sha256:<64 hex digits>.
pinned_re='^[A-Za-z0-9_][A-Za-z0-9_.-]*@sha256:[0-9a-f]{64}$'
# A minor line, as in 0.1.
line_re='^[0-9]+\.[0-9]+$'
phyllon='ghcr[.]io/nemesis398/phyllon'
caddy='docker[.]io/library/caddy'
pgvector='docker[.]io/pgvector/pgvector'
# Optional blanks.
s='[[:space:]]*'

# Finds the one line of $1 that matches the extended regular expression $3 and
# sets value to the regex's first group and lineno to the line's number. $2
# describes the line for the message. Records a failure and returns 1 when the
# file is missing or has no such line or more than one.
value=""
lineno=0
find_one() {
	local file="$1" what="$2" re="$3" line n=0 first=0
	value=""
	lineno=0
	if [[ ! -f "$root/$file" ]]; then
		failures+=("$file: missing or not a file")
		return 1
	fi
	while IFS= read -r line || [[ -n "$line" ]]; do
		n=$((n + 1))
		line="${line%$'\r'}"
		[[ "$line" =~ $re ]] || continue
		if ((first > 0)); then
			failures+=("$file:$n: more than one line $what, first at line $first")
			return 1
		fi
		first=$n
		value="${BASH_REMATCH[1]}"
	done <"$root/$file"
	if ((first == 0)); then
		failures+=("$file: no line $what")
		return 1
	fi
	lineno=$first
}

# Checks that $file:$lineno pins $value by tag and digest. $1 names the image.
pinned() {
	[[ "$value" =~ $pinned_re ]] && return 0
	failures+=("$file:$lineno: $1:$value is not pinned by tag and digest")
	return 1
}

# Caddy and pgvector: each unit must name compose.yaml's reference.
compose_pgvector=""
compose_pgvector_line=0
for image in caddy pgvector; do
	case "$image" in
	caddy)
		name="$caddy" shown=docker.io/library/caddy
		unit=deploy/quadlet/phyllon-proxy.container label=Caddy
		;;
	pgvector)
		name="$pgvector" shown=docker.io/pgvector/pgvector
		unit=deploy/quadlet/phyllon-db.container label=pgvector
		;;
	esac
	file=compose.yaml
	ref=""
	if find_one "$file" "image: $shown:TAG@DIGEST" "^${s}image:${s}${name}:([^[:space:]]+)${s}\$" &&
		pinned "$shown"; then
		ref="$value"
		ref_line="$lineno"
	fi
	if [[ "$image" == pgvector && -n "$ref" ]]; then
		compose_pgvector="$ref"
		compose_pgvector_line="$ref_line"
	fi
	file="$unit"
	if find_one "$file" "Image=$shown:TAG@DIGEST" "^Image=${name}:([^[:space:]]+)${s}\$" &&
		pinned "$shown" && [[ -n "$ref" && "$value" != "$ref" ]]; then
		failures+=("$file:$lineno: $label is $shown:$value, but compose.yaml:$ref_line has $shown:$ref")
	fi
done

# pgvector in ci.yml: the integration entry for compose.yaml's major version.
file=.github/workflows/ci.yml
if [[ -n "$compose_pgvector" ]]; then
	tag="${compose_pgvector%%@*}"
	digest="${compose_pgvector#*@}"
	if [[ ! "$tag" =~ -pg([0-9]+)$ ]]; then
		failures+=("compose.yaml:$compose_pgvector_line: the pgvector tag $tag names no PostgreSQL major version (-pgN)")
	elif [[ ! -f "$root/$file" ]]; then
		failures+=("$file: missing or not a file")
	else
		major="${BASH_REMATCH[1]}"
		postgres_re="^${s}-${s}postgres:${s}([0-9]+)${s}\$"
		image_re="^${s}image:${s}(docker[.]io/)?pgvector/pgvector(:([^@[:space:]]+))?@(sha256:[0-9a-f]{64})${s}(#${s}([^[:space:]]+))?${s}\$"
		current=""
		found=0
		n=0
		while IFS= read -r line || [[ -n "$line" ]]; do
			n=$((n + 1))
			line="${line%$'\r'}"
			if [[ "$line" =~ $postgres_re ]]; then
				current="${BASH_REMATCH[1]}"
				continue
			fi
			[[ "$current" == "$major" && "$line" =~ $image_re ]] || continue
			if ((found > 0)); then
				failures+=("$file:$n: more than one pgvector image for postgres: $major, first at line $found")
				break
			fi
			found=$n
			ci_digest="${BASH_REMATCH[4]}"
			ci_tag="${BASH_REMATCH[3]:-${BASH_REMATCH[6]}}"
			if [[ "$ci_digest" != "$digest" || "$ci_tag" != "$tag" ]]; then
				failures+=("$file:$n: pgvector for postgres: $major is ${ci_digest} (tag ${ci_tag:-none}), but compose.yaml:$compose_pgvector_line has $digest (tag $tag)")
			fi
		done <"$root/$file"
		((found > 0)) ||
			failures+=("$file: no pgvector entry for postgres: $major, which compose.yaml:$compose_pgvector_line runs")
	fi
fi

# The Phyllon minor line: every file must name compose.yaml's.
minor_files=(
	compose.yaml
	.env.example
	deploy/quadlet/phyllon.container
	.github/workflows/nightly.yml
	.github/workflows/podman.yml
	scripts/quadlet-test.sh
)
# How each line looks, for the messages. The ${...} is shown, not expanded.
# shellcheck disable=SC2016
minor_whats=(
	'image: ${PHYLLON_IMAGE:-ghcr.io/nemesis398/phyllon:LINE}'
	'PHYLLON_IMAGE=ghcr.io/nemesis398/phyllon:LINE'
	'Image=ghcr.io/nemesis398/phyllon:LINE'
	'image: ghcr.io/nemesis398/phyllon:LINE'
	'podman tag localhost/phyllon:ci ghcr.io/nemesis398/phyllon:LINE'
	'image=ghcr.io/nemesis398/phyllon:LINE'
)
minor_res=(
	"^${s}image:${s}[\$][{]PHYLLON_IMAGE:-${phyllon}:([^}[:space:]]*)[}]${s}\$"
	"^PHYLLON_IMAGE=${phyllon}:([^[:space:]]*)${s}\$"
	"^Image=${phyllon}:([^[:space:]]*)${s}\$"
	"^${s}image:${s}${phyllon}:([^[:space:]]*)${s}\$"
	"^${s}podman tag localhost/phyllon:ci ${phyllon}:([^[:space:]]*)${s}\$"
	"^image=${phyllon}:([^[:space:]]*)${s}\$"
)
minor=""
minor_line=0
for i in "${!minor_files[@]}"; do
	file="${minor_files[$i]}"
	find_one "$file" "${minor_whats[$i]}" "${minor_res[$i]}" || continue
	if [[ ! "$value" =~ $line_re ]]; then
		failures+=("$file:$lineno: the Phyllon image names $value, which is not a minor line such as 0.1")
		continue
	fi
	if [[ "$file" == compose.yaml ]]; then
		minor="$value"
		minor_line="$lineno"
	elif [[ -n "$minor" && "$value" != "$minor" ]]; then
		failures+=("$file:$lineno: the Phyllon minor line is $value, but compose.yaml:$minor_line has $minor")
	fi
done

if ((${#failures[@]} > 0)); then
	printf '%s\n' "${failures[@]}"
	echo "check-image-pins.sh: ${#failures[@]} problem(s) with the image references"
	exit 1
fi
echo "check-image-pins.sh: Caddy, pgvector and the Phyllon minor line agree (Phyllon $minor)"
