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

failed=0
pass() { echo "PASS $1"; }
fail() {
	echo "FAIL $1"
	failed=$((failed + 1))
}

if ! compose up --detach --wait --wait-timeout 180; then
	compose ps --all
	compose logs --no-color --tail 50
	echo "stack-test.sh: the stack did not become healthy" >&2
	exit 1
fi

# Runs SQL $2 in the db container as role $1 over TCP, with the role's
# password from its file, so the password is never on a command line.
sql() {
	local file
	case "$1" in
	postgres) file=db_superuser_password ;;
	phyllon_owner) file=db_owner_password ;;
	phyllon_runtime) file=db_runtime_password ;;
	*) return 2 ;;
	esac
	# shellcheck disable=SC2016 # the container's shell expands it
	compose exec -T db sh -c \
		'PGPASSWORD="$(cat "/run/secrets/$1")" exec psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$2" -d phyllon -At -c "$3"' \
		sh "$file" "$1" "$2"
}

for path in /healthz /readyz; do
	code="$(curl -sk -o /dev/null -w '%{http_code}' "https://localhost:8443$path" || true)"
	if [[ "$code" == 200 ]]; then pass "$path answers 200"; else fail "$path answers $code, want 200"; fi
done

# The answers are read from stdout; stderr goes to a file for the message.
out="$(sql postgres 'SHOW password_encryption' 2>"$work/err" || true)"
if [[ "$out" == scram-sha-256 ]]; then
	pass "password_encryption is scram-sha-256"
else
	fail "password_encryption is '$out', want scram-sha-256: $(<"$work/err")"
fi

# Every rule must be SCRAM, so neither trust nor md5 (nor anything else) is
# left, and a file that could not be read must not pass as empty.
out="$(sql postgres "SELECT count(*) FILTER (WHERE auth_method <> 'scram-sha-256' OR error IS NOT NULL) || ' ' || count(*) FROM pg_hba_file_rules" 2>"$work/err" || true)"
if [[ "$out" =~ ^0\ [1-9][0-9]*$ ]]; then
	pass "every pg_hba rule is scram-sha-256"
else
	fail "pg_hba holds other rules (non-SCRAM and total: '$out'): $(<"$work/err")"
	sql postgres 'SELECT line_number, type, database, user_name, auth_method, error FROM pg_hba_file_rules' || true
fi

# The owner creates a table; the runtime role may use it but create none.
if sql phyllon_owner 'CREATE TABLE owned (i int)' >/dev/null 2>&1 &&
	sql phyllon_runtime 'INSERT INTO owned VALUES (1); SELECT count(*) FROM owned' >/dev/null 2>&1; then
	pass "phyllon_runtime writes the tables phyllon_owner creates"
else
	fail "phyllon_owner cannot create a table, or phyllon_runtime cannot write it"
fi
out="$(sql phyllon_runtime 'CREATE TABLE t (i int)' 2>&1 || true)"
if [[ "$out" == *"permission denied"* ]]; then
	pass "phyllon_runtime cannot create a table"
else
	fail "CREATE TABLE as phyllon_runtime answered: $out"
fi

if "$root/scripts/posture.sh" "$engine" "$project"; then
	pass "posture"
else
	fail "posture"
fi

if ((failed > 0)); then
	echo "stack-test.sh: $failed checks failed"
	exit 1
fi
echo "stack-test.sh: every check passed"
