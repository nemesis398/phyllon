# 0002: One package with a library and a binary

Date: 2026-10-29

Status: accepted

## Context

Phyllon starts as one binary with two subcommands, `serve` and `healthcheck`,
and five modules in `src/`: `cli`, `config`, `db`, `http` and `web`. They hold
989 lines when this record was written. Later phases add more, such as an MCP
server, OAuth and Typst rendering, and a contributor may ask whether each of
those should be a crate of its own.

Four facts bear on the layout:

- The [phase 1 design](../specs/2026-10-29-phase-1-foundations-design.md) lists
  the crate layout as a call: one package, `phyllon`, with a library and a
  binary target, and a workspace "when a second crate earns its place".
- Cargo links a test in `tests/` against the package's library, never against
  its binary, so code that integration tests must reach has to live in a library
  target.
- Cargo applies `[lints]` per package. The
  [engineering research](../research/engineering-quality.md) could not verify
  which release added `[workspace.lints]` inheritance, and marks it
  **unverified**.
- `http` and `web` use each other. `http::router` mounts `web::routes`, and
  `web` takes `AppState` from `http`. Crates cannot depend on each other in a
  circle.

## Options

1. **One package** with a library, whose root is `src/lib.rs`, and a binary,
   `src/main.rs`, that only calls `phyllon::cli::run`.
2. **A workspace of several crates** from the start, for example one for the web
   layer, one for the database and one for the command line.
3. **A binary only**, with no library. The tests would start the binary as a
   process and talk to it over a socket.

| Dial         | One package                                                   | A workspace of several crates                                              | A binary only                                                  |
| ------------ | ------------------------------------------------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Granularity  | The module is the finest unit, and nothing enforces its edge  | The crate is a finer unit, and the compiler enforces its edge              | One unit, and tests can only see it from outside               |
| Redundancy   | One `Cargo.toml`, one `[lints]` table and one lockfile entry  | Each member repeats its manifest, or inherits lints from the workspace     | One manifest, as in option 1                                   |
| Coupling     | Modules may use each other, so `http` and `web` need no split | A cycle between crates is impossible, so `AppState` would have to move out | Not at stake                                                   |
| Retention    | Not at stake                                                  | Not at stake                                                               | Not at stake                                                   |
| Flow control | A test calls a function in the library                        | A test calls a function in the crate that owns it                          | A test goes through a process, a socket and a start-up timeout |

## Decision

Use option 1. Keep one Cargo package, `phyllon`, whose library holds every
module and whose binary stays a call to `phyllon::cli::run`. Put no logic in
`src/main.rs`.

Add a second crate only when it earns its place, for example when something must
build, test or release apart from the rest, and write a new record that
supersedes this one when that happens.

## Consequences

- One manifest carries the lint table, the dependency list and the version, so
  the gate (`scripts/check.sh`) and the release have one package to handle.
- Tests in `tests/` call the library directly, which `tests/http.rs` and
  `tests/config.rs` do.
- Nothing but convention keeps a module out of another's internals. The
  invariants in [the module map](../map.md) and its CI check stand in for the
  boundary a crate would enforce.
- `http` and `web` can keep using each other. A split of `web` into its own
  crate would first need `AppState` and `BuildInfo` to move to a crate both
  depend on.
- Revisit this when the library grows a part that needs a different dependency
  set or release rhythm than the rest.
