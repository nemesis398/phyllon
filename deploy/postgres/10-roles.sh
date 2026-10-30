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
# psql reads each password itself, with a backtick meta-command, so no
# password is ever on a command line, where any user of the host could read it
# in /proc. The statements quote them with :'name', so no character in them
# can end the literal, and the script never prints them. sed turns a final
# "\r\n" into "\n" and psql drops the final "\n", which is how Phyllon reads a
# password file, so both sides agree on the password. --single-transaction
# makes a failed run leave no role behind.

set -euo pipefail

# psql sets a variable to an empty string when the backtick command fails, and
# carries on, so check the files first. The content stays in this process.
for file in /run/secrets/db_owner_password /run/secrets/db_runtime_password; do
	if ! password="$(sed -z 's/\r\n$/\n/' "$file")" || [[ -z "$password" ]]; then
		echo "10-roles.sh: cannot read a password from $file" >&2
		exit 1
	fi
done
unset password

psql -v ON_ERROR_STOP=1 --no-psqlrc --single-transaction --username postgres \
	--dbname phyllon --file - <<'SQL'
\set owner_password `sed -z 's/\r\n$/\n/' /run/secrets/db_owner_password`
\set runtime_password `sed -z 's/\r\n$/\n/' /run/secrets/db_runtime_password`

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
