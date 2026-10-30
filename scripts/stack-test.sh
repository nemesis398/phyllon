#!/usr/bin/env bash
# Starts the compose stack the way docs/install.md does, checks it and removes
# it again. Run it with:
#
#   scripts/stack-test.sh ENGINE [IMAGE]
#
# ENGINE is docker or podman. IMAGE replaces PHYLLON_IMAGE from .env.example,
# for example an image built from this checkout. The stack runs from a copy of
# compose.yaml and deploy/ in a temporary directory, with its own .env and
# secrets/, so the checkout's own files stay untouched. The project and its
# volumes are removed at the end, whatever happened. Exit 0 means every check
# passed.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project=phyllon-stack-test

case "${1:-}" in
docker | podman) engine="$1" ;;
*)
	echo "usage: scripts/stack-test.sh docker|podman [IMAGE]" >&2
	exit 2
	;;
esac
image="${2:-}"
# podman compose prints a banner about its provider on every call.
export PODMAN_COMPOSE_WARNING_LOGS=false

work="$(mktemp -d -p "${TMPDIR:-/tmp}" phyllon-stack-test.XXXXXX)"
compose() {
	"$engine" compose --file "$work/compose.yaml" --project-directory "$work" \
		--project-name "$project" "$@"
}
cleanup() {
	compose down --volumes --remove-orphans --timeout 10 >/dev/null 2>&1 ||
		echo "stack-test.sh: compose down failed; remove the project $project by hand" >&2
	rm -rf -- "$work"
}
trap cleanup EXIT

cp -- "$root/compose.yaml" "$work/"
cp -R -- "$root/deploy" "$work/"
if [[ -n "$image" ]]; then
	{
		command grep -v '^PHYLLON_IMAGE=' "$root/.env.example"
		printf 'PHYLLON_IMAGE=%s\n' "$image"
	} >"$work/.env"
else
	cp -- "$root/.env.example" "$work/.env"
fi
# The install guide's commands: a directory only its owner can enter, and
# password files every container user may read (see compose.yaml).
mkdir -m 700 "$work/secrets"
for name in db_superuser_password db_owner_password db_runtime_password; do
	(umask 222 && openssl rand -base64 32 >"$work/secrets/$name")
done

if ! compose up --detach --wait --wait-timeout 180; then
	compose ps --all
	compose logs --no-color --tail 50
	echo "stack-test.sh: the stack did not become healthy" >&2
	exit 1
fi

db_exec() { compose exec -T db "$@"; }
# shellcheck source=scripts/stack-checks.sh source-path=SCRIPTDIR/..
source "$root/scripts/stack-checks.sh"
stack_checks "$engine" "$project"

if ((failed > 0)); then
	echo "stack-test.sh: $failed checks failed"
	exit 1
fi
echo "stack-test.sh: every check passed"
