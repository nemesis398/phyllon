# 0003: axum with askama templates

Date: 2026-10-29

Status: accepted

## Context

Phase 1 serves two health routes and a web UI shell: a start page, two error
pages and some assets. Phase 2 adds sign-in and an MCP server on the same
binary. The [main design](../specs/2026-10-29-phyllon-design.md) leaves "the
HTML templating for the web UI" to the builder, and the
[phase 1 design](../specs/2026-10-29-phase-1-foundations-design.md) records the
call: axum, with server-rendered HTML from askama templates, and a shell that
ships no JavaScript.

What bears on it:

- The [technical check](../research/tech-check.md) found that the MCP SDK `rmcp`
  offers its Streamable HTTP server as a Tower service that nests into an axum
  router with `nest_service("/mcp", service)`, and that the server side of
  authentication is axum middleware. It did not check other HTTP frameworks, and
  this record does not compare them.
- The security baseline of
  [the standards research](../research/standards-security.md) asks for a CSP of
  `default-src 'self'` and no third-party assets (item 18), and for a UI that
  makes no third-party request (item 9). A page that needs inline script or a
  CDN conflicts with both.
- The release is a static binary in a distroless image, which has no shell. The
  design lets the shell compile its assets into the binary.
- askama's README says it generates "type-safe Rust code from your templates at
  compile time based on a user-defined `struct`" and compiles the template code
  into the crate. Its default escaper for `.html` templates is the HTML escaper
  (`askama_derive` 0.16.1, `src/config.rs`). The same README says that askama
  was forked into Rinja and later merged back.
- The phase 1 design allows Node code only for the browser test in
  `tests/browser/`.

## Options

1. **axum with askama**: handlers return HTML rendered from compiled templates.
2. **axum with a runtime template engine**, which loads template files or
   strings when the server runs.
3. **axum as a JSON API and a separate single-page app** that renders in the
   browser.

| Dial         | axum with askama                                                      | axum with a runtime engine                                        | JSON API and a single-page app                                      |
| ------------ | --------------------------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------- |
| Granularity  | A page is one struct and one template, and the struct is checked      | A page is a template and an untyped context                       | Two units, the API and the app, built apart                         |
| Redundancy   | One route table, and the strings are constants in `strings.rs`        | One route table, as in option 1                                   | A route table in the server and another in the browser              |
| Coupling     | Templates and structs change together, and a mismatch fails the build | Templates can change without a build, and a typo fails at runtime | Needs a Node toolchain and script files that the CSP must allow     |
| Retention    | Not at stake                                                          | Not at stake                                                      | The app keeps a copy of server state that it must keep in sync      |
| Flow control | A handler calls `render()` and returns the string                     | A handler calls the engine, as in option 1                        | The page's script decides when to call, and the server only answers |

## Decision

Use option 1. Build the HTTP layer with axum and render pages with askama
templates from `templates/`, compiled into the binary. A handler renders to a
`String` and returns `Html`, with no askama integration crate. The shell ships
no JavaScript. When phase 2 needs a script, it is a file under `/assets`,
because the CSP forbids inline scripts.

Mount the MCP service of phase 2 as its own router, not in the router that holds
the web routes, as the
[phase 1 design](../specs/2026-10-29-phase-1-foundations-design.md) asks under
"Doors phase 1 keeps open".

## Consequences

- The static binary needs no template directory at run time, and a template
  error is a build error.
- askama escapes HTML by default, so a value reaches a page escaped unless a
  template says otherwise. A template that opts out of escaping is a place for a
  reviewer to look.
- Changing a template means a rebuild. Nobody can edit a page on a running
  server, which is the price of the checks above.
- Interactivity beyond forms needs script files that obey the CSP. The shell
  tests assert that no page carries a `<script` tag, and phase 2 changes that
  test with its first script.
- The `askama` crate was forked as Rinja and merged back. Check its maintenance
  when a new major version arrives, and write a new record if the templating
  changes.
- This record chose axum for its fit with `rmcp`. It does not claim that no
  other framework would do.
