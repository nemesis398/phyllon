#!/usr/bin/env bash
# Creates the vector extension and Phyllon's two roles in the phyllon
# database. The image's entrypoint runs it once, when the data volume is new,
# as postgres against the server it started for initialization, with
# PGPASSWORD set to the superuser's password.
#
# phyllon_owner owns the database and runs the migrations. phyllon_runtime is
# what Phyllon connects as: it may read and write the tables phyllon_owner
# creates, and create nothing.
#
# The passwords reach psql as variables and the SQL quotes them with :'name',
# so no character in them can end the literal. The script never prints them.

set -euo pipefail

# Prints the content of file $1 without one trailing "\n" or "\r\n", the way
# Phyllon reads a password file, so both sides agree on the password.
read_password() {
	local text
	text="$(cat -- "$1" && printf x)"
	text="${text%x}"
	if [[ "$text" == *$'\r\n' ]]; then
		text="${text%$'\r\n'}"
	else
		text="${text%$'\n'}"
	fi
	printf '%s' "$text"
}

owner_password="$(read_password /run/secrets/db_owner_password)"
runtime_password="$(read_password /run/secrets/db_runtime_password)"

psql -v ON_ERROR_STOP=1 --no-psqlrc --username postgres --dbname phyllon \
	-v owner_password="$owner_password" -v runtime_password="$runtime_password" <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;

CREATE ROLE phyllon_owner LOGIN PASSWORD :'owner_password';
ALTER DATABASE phyllon OWNER TO phyllon_owner;

-- PUBLIC may connect and create temporary tables by default. Now only the
-- owner (and superusers) may, and phyllon_runtime may only connect.
REVOKE ALL ON DATABASE phyllon FROM PUBLIC;
CREATE ROLE phyllon_runtime LOGIN PASSWORD :'runtime_password';
GRANT CONNECT ON DATABASE phyllon TO phyllon_runtime;

-- Since PostgreSQL 15 PUBLIC has only USAGE on the public schema, and the
-- database owner owns it, so phyllon_owner may create tables there and
-- phyllon_runtime may not.
GRANT USAGE ON SCHEMA public TO phyllon_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE phyllon_owner IN SCHEMA public
	GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO phyllon_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE phyllon_owner IN SCHEMA public
	GRANT USAGE, SELECT ON SEQUENCES TO phyllon_runtime;
SQL
