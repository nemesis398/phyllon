# Module map

This map lists each module of `src/`, what it owns, the invariants it keeps and
the decision records behind it. Read the entry of a module before you change it,
and read [the package](#the-package) first.

Each invariant here is true of the code today, or is marked as a rule for a
later phase. If a change breaks one, change the code back, or change this map in
the same pull request and say why in its description. If you add a module, add
its entry.

`scripts/ci/check-map.sh` keeps the map and `src/` in step. It fails on a module
without an entry and on an entry without a module. An entry is a heading of
exactly the form `` ## `name` ``, one per module. The files directly in `src/`
(other than `lib.rs` and `main.rs`) and the directories directly in `src/` are
the modules. A file below one, such as `src/http/headers.rs`, is part of its
module and has no entry of its own.

## The package

Phyllon is one Cargo package with a library, whose root is `src/lib.rs`, and a
binary, `src/main.rs`, which only calls [`cli::run`](../src/cli.rs). Everything
else is a module of the library, so the tests in `tests/` reach it. The modules
may use each other freely (`http` and `web` do), and the compiler enforces no
boundary between them, so the invariants below and this map carry that work.

Decision records: [0002](decisions/0002-one-package.md) explains the layout, and
[0001](decisions/0001-decision-records.md) the format of the records.

## `cli`

Source: [`src/cli.rs`](../src/cli.rs)

**Owns.** The `phyllon` command: `serve`, which runs the server until SIGTERM or
SIGINT, and `healthcheck`, which asks the server on this host for `/healthz`.
The `--config` option (or `PHYLLON_CONFIG`), the order of start-up, the logging
set-up, the signal handlers, the exit codes, and the probe that `healthcheck`
uses.

**Invariants.**

- The config file is the only configuration. The commands take one option,
  `--config`, and `serve` refuses to start while `PGOPTIONS` is set, because
  that variable can change any setting of the database sessions and sqlx cannot
  clear it.
- A failure prints `phyllon: <reason>` on stderr and exits 1, and a usage error
  exits 2. The error for a secret file names its key and path, never its
  content, and a parse error of the config file quotes no text of the file (see
  `config`).
- The database password is read into a `Secret` once, by `serve`, and handed
  only to `db::pool`. The log lines `serve` writes, at level INFO, hold the
  version, the commit and the listen address, or say that the server is
  stopping.
- `healthcheck` reads the config file and nothing else: not the password file,
  not the database.
- The probe is bounded. It takes about three seconds at most, reads at most 64
  bytes of the answer, and succeeds only on `HTTP/1.1 200`.
- Both signal handlers are installed before the server listens, and on a signal
  the requests in flight finish and the pool closes.

**Decision records.** None of its own. [0002](decisions/0002-one-package.md)
explains why `main.rs` is five lines that call `cli::run`.

## `config`

Source: [`src/config.rs`](../src/config.rs)

**Owns.** The TOML configuration file, its validation, and the secrets it points
to. Types: `Config`, `DatabaseConfig`, `Secret`, `ConfigError` and `ParseError`.

**Invariants.**

- The config file must hold no secret. A secret lives in its own file, which a
  `*_file` key names (`database.password_file`), and `Config::load` does not
  read it. `DatabaseConfig::password` reads it, strips one trailing line ending
  and nothing else, and returns a `Secret`.
- In `Display` and `Debug`, a `ConfigError::Parse` holds the kind of error, the
  keys involved and a line and column, but no other text of the config file. So
  a secret pasted into the file, such as a `password` key that
  `deny_unknown_fields` rejects, does not reach the log through the error.
  Syntax messages come from static text in the `toml` parser. Serde messages are
  rebuilt from known shapes with the value cut out, and any other shape is
  withheld.
- A `Secret` cannot leak through `Debug`: `{:?}` and `{:#?}` print
  `Secret([redacted])`. Its text comes out only through `Secret::expose`, whose
  one caller is `db::pool`.
- No `ConfigError` variant carries or prints the content of a secret file. The
  error for an unreadable secret names the key and the path.
- Unknown keys are errors in every table (`deny_unknown_fields`), so a
  misspelled key cannot fall back to a default unnoticed.
- `Config::load` guarantees that `public_url` starts with `https://` or
  `http://`, and so does a set `source_url`, because the site links to it.

**Decision records.** None yet.

## `db`

Source: [`src/db.rs`](../src/db.rs)

**Owns.** The PostgreSQL connection pool and the readiness check behind
`/readyz`.

**Invariants.**

- `db::pool` does not connect. The first connection opens when the pool is first
  used, so a database that is down at start-up does not stop the server, and
  `/readyz` reports it.
- The config is the only source of the connection settings. The options start
  from `PgConnectOptions::new_without_pgpass`, and host, port, user, database,
  password, TLS mode and application name are all set explicitly, so no `PG*`
  variable or `~/.pgpass` changes them. The two exceptions, `PGOPTIONS` and the
  TLS certificate paths, cannot be cleared in sqlx 0.9.0. The certificate paths
  do nothing while TLS is off, and `serve` refuses to start while `PGOPTIONS` is
  set. The TLS mode is `Disable`, because sqlx is built without a TLS feature.
- The password reaches sqlx only through the connect options, which are not
  logged. `Secret::expose` is called nowhere else in `src/`.
- No request waits more than two seconds for a connection, and `db::ready` takes
  two seconds in total at most, whatever the database does. It returns a `bool`,
  never an error.

**Decision records.** None yet.

## `http`

Source: [`src/http/mod.rs`](../src/http/mod.rs), with the headers in
[`src/http/headers.rs`](../src/http/headers.rs)

**Owns.** The router and its state (`AppState`, `BuildInfo`), the one error type
(`AppError`), the security headers, the panic catching, the health routes
`/healthz` and `/readyz`, and `source_url`, which says where the source of the
running version is offered.

**Invariants.**

- Every response passes `with_security_layers`. `router` ends by wrapping its
  whole route set, the 404 fallback included, in it, so every response carries
  the five headers of `SECURITY_HEADERS`, errors too. A route added outside
  `router` must be wrapped the same way.
- Phyllon sets the headers itself and leaves none to the proxy, so they hold
  behind whatever proxy a deployer runs.
- A panic in a handler becomes a generic 500 that carries the same headers. The
  panic message never reaches the client; it stays in the panic hook's output.
- `AppError` has one variant, and its response says nothing about the cause, so
  no internal detail reaches a client.
- `/healthz` does not touch the database. `/readyz` answers 200 or 503 from
  `db::ready`. Both answer `HEAD` too.
- Cookie and bearer authentication never share a route. The phase 1 design asks
  for separate routers for the web UI and for `/mcp` and `/mcp/admin` (section
  "Doors phase 1 keeps open"), so the web routes and the MCP routes of phase 2
  each get their own `Router` with their own authentication layer, and no layer
  spans both. This is a rule for phase 2. It holds today because no MCP route
  exists and `router` carries only the health routes and the web routes.

**Decision records.** [0003](decisions/0003-axum-and-askama.md) chose axum.
[0004](decisions/0004-caddy.md) relies on this: the headers are set here and not
in the bundled proxy, so they hold behind a deployer's own proxy (the design's
section "Behind an existing proxy").

## `web`

Source: [`src/web/mod.rs`](../src/web/mod.rs), with the strings in
[`src/web/strings.rs`](../src/web/strings.rs); the templates are in
[`templates/`](../templates) and the assets in [`assets/`](../assets) and
[`brand/`](../brand)

**Owns.** The web UI shell: the start page, the branded 404 and 500 pages, and
the assets under `/assets/`. Every English string a page shows.

**Invariants.**

- The assets are compiled into the binary and looked up by name in a fixed
  table, so a request path never becomes a file path. A name not in the table,
  and a path that is not valid UTF-8 once decoded, get the branded 404.
- Pages load nothing from another origin and hold no script, no style block and
  no inline style. The tests in `tests/web.rs` check the start page, the 404
  page and the 500 page.
- Every English string a page shows is a constant in `strings.rs`, so phase 2
  can move them into Fluent files without searching the templates.
- A page that fails to render gets the branded 500 page. If that page fails too,
  the answer is a plain-text 500, since nothing else is left to try. That
  fallback, `internal server error`, is the one string outside `strings.rs`.
- The 500 page says nothing about the cause. Pages that know the running build
  show its version and the source link of `http::source_url`; the 500 page has
  no build at hand and leaves both out.
- `web::routes` returns a router with no state, layers or fallback. The module
  sets no security header, because `http::router` wraps the routes it mounts.

**Decision records.** [0003](decisions/0003-axum-and-askama.md) chose askama,
the compiled-in templates and the shell without JavaScript.
