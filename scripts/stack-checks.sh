# shellcheck shell=bash
# The checks that scripts/stack-test.sh and scripts/quadlet-test.sh both run on
# a started stack, sourced by each. Before calling stack_checks, the caller
# defines db_exec, which runs its arguments in the PostgreSQL container as the
# container's user with stdin attached, and sets work to a directory for
# scratch files. Then:
#
#   stack_checks ENGINE PROJECT
#
# prints PASS or FAIL per check and adds each failure to failed. PROJECT is
# the compose project label scripts/posture.sh selects the containers by.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

failed=0
pass() { echo "PASS $1"; }
fail() {
	echo "FAIL $1"
	failed=$((failed + 1))
}

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
	db_exec sh -c \
		'PGPASSWORD="$(cat "/run/secrets/$1")" exec psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$2" -d phyllon -At -c "$3"' \
		sh "$file" "$1" "$2"
}

stack_checks() {
	local path code out
	: "${work:?the caller sets work}"
	for path in /healthz /readyz; do
		code="$(curl -sk -o /dev/null -w '%{http_code}' "https://localhost:8443$path" || true)"
		if [[ "$code" == 200 ]]; then pass "$path answers 200"; else fail "$path answers $code, want 200"; fi
	done

	# The start page is the shell's HTML, through Caddy. The branded 404 and 500
	# say "Phyllon" too, so the check wants status 200 and a sentence that only
	# the start page holds.
	code="$(curl -sk -o "$work/start.html" -w '%{http_code}' "https://localhost:8443/" || true)"
	if [[ "$code" == 200 ]] && command grep -qF 'There is nothing to sign in to yet.' "$work/start.html"; then
		pass "/ is the start page"
	else
		fail "/ answers $code, want 200 with the start page"
	fi

	# The answers are read from stdout; stderr goes to a file for the message.
	out="$(sql postgres 'SHOW password_encryption' 2>"$work/err" || true)"
	if [[ "$out" == scram-sha-256 ]]; then
		pass "password_encryption is scram-sha-256"
	else
		fail "password_encryption is '$out', want scram-sha-256: $(<"$work/err")"
	fi

	# Every rule must be SCRAM, so neither trust nor md5 (nor anything else)
	# is left, and a file that could not be read must not pass as empty.
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

	if "$(dirname "${BASH_SOURCE[0]}")/posture.sh" "$1" "$2"; then
		pass "posture"
	else
		fail "posture"
	fi
}
