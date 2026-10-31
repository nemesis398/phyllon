# Agent rules

These rules apply to every AI agent that works in this repository, whichever
tool runs it. They are short on purpose. Hooks and CI enforce the ones that
matter most, because an instruction file alone does not reliably change what an
agent does.

## Rules

1. **Run the full gate before you say done, and show the output.** The gate is
   `scripts/check.sh`: format, clippy with warnings denied, tests, doctests and
   the dependency checks. A model does not reliably find its own errors, but
   compiler and test feedback does fix them.
2. **Write the failing test first, run it, watch it fail, then implement.** A
   test that never failed may not exercise your code.
3. **Never weaken a gate to get green.** The gate's files are `Cargo.toml`
   `[lints]`, `clippy.toml`, `deny.toml`, `rust-toolchain.toml`,
   `release-plz.toml`, `package.json`, `playwright.config.ts`,
   `.github/workflows/`, `.github/dependabot.yml`, `.githooks/`,
   `.claude/settings.json`, `scripts/check.sh`, `scripts/hooks/`, `scripts/ci/`,
   `scripts/posture.sh`, `scripts/stack-checks.sh`, `tests/browser/`,
   `.prettierrc.yaml`, `.prettierignore` and `.markdownlint-cli2.yaml`. Change
   them, add an `#[allow]` without a written reason, or `#[ignore]` or delete a
   test only with the maintainer's explicit approval in the pull request,
   because a verifier the agent can edit stops being one.
4. **No `unsafe`, `unwrap`, `expect`, `panic!`, `todo!` or unchecked indexing
   outside tests.** Return typed errors, because a panic on request input is a
   denial-of-service bug.
5. **Write SQL through `sqlx::query!` and its macro family, with bound
   parameters.** Never build SQL with `format!`. Commit `.sqlx` and keep
   `cargo sqlx prepare --check` green once queries exist. This does not forbid
   sqlx's connection ping. Injection and XSS are the most common failures in the
   security benchmarks, and compile-time checks catch invented columns.
6. **Treat every external input as hostile and validate it at the boundary.**
   That covers HTTP bodies, tool arguments, uploaded files, fetched URLs, file
   paths and model output. Give each new parser a size limit and a property test
   or fuzz target, because about half of the correct programs in security
   benchmarks were still exploitable.
7. **Do not add or bump a dependency without a justification in the pull
   request:** name, purpose, license, maintainer, last release, and proof that
   it exists on crates.io. Take the newest release that is at least 7 days old,
   use no git or path dependencies, and commit the lockfile, because models
   invent packages and a poisoned crate runs code at build time.
8. **Read the docs for the pinned version before you use a crate API.** Use
   docs.rs or the source in `~/.cargo/registry`, not memory, because models
   write worse code against APIs newer than their training data.
9. **Keep diffs small.** One concern per pull request, about 400 changed lines
   at most, not counting lockfiles, generated files and vendored text. Every
   pull request is squash merged, so its title is a conventional commit of at
   most 72 characters, because review quality drops on large diffs and the
   maintainer is the only reviewer.
10. **Plan before code for anything beyond a small fix.** Write a short spec in
    the pull request or in `docs/`: behavior, edge cases, non-goals, the tests
    and the sources. Wait for approval on design-level choices such as schema,
    public API and auth, because design and security judgment came from humans
    in the cases studied.
11. **Cover edge cases on purpose:** empty, maximum size, Unicode, negative,
    duplicate, concurrent and malformed input. Use property tests for invariants
    such as roundtrip, idempotence and ordering. Run `cargo mutants --in-diff`
    on your change and kill surviving mutants by strengthening tests, never by
    deleting code, because coverage shows lines reached, not lines checked.
12. **Ask for a separate review, and verify what it says.** Give a fresh session
    the diff and the spec but not your reasoning, plus a security checklist:
    authorization on every endpoint and tool, injection, SSRF, path traversal,
    secrets in logs, prompt injection into tools, and unbounded input. Turn each
    finding into a failing test before you act on it, because a model reviewing
    its own work in the same context adds little.
13. **Measure before you optimize.** Attach a profile or a benchmark delta to
    every performance change, and check the database before Rust CPU, because
    optimization without a measurement adds complexity for no proven gain.
14. **Keep money and secrets out of tests and code.** `cargo test` never touches
    the network by default. Paid-API tests live behind a feature flag or
    `#[ignore]`, read keys from the environment only in the protected CI
    environment, and use recorded fixtures elsewhere. Never log keys or full
    request bodies, and never edit a workflow to add secret access, because an
    untrusted pull request must not spend money.
15. **Report honestly and explain.** End each pull request description with what
    you ran, what you did not run, and what you are unsure of, and mark claims
    you did not verify. Explain any non-obvious design choice in two or three
    sentences, because the maintainer must be able to review what ships.
16. **Add a sign-off only when the person who directs you has told you to
    commit.** Then add that person's `Signed-off-by:` line and your own
    `Co-Authored-By:` trailer. That person reviews the pull request before it
    merges, because the sign-off is a certification only a human can make. See
    [CONTRIBUTING.md](CONTRIBUTING.md).

## Where things live

- `docs/specs/`: the designs, one per piece of work.
- `docs/plans/`: the implementation plans that follow a design.
- `docs/decisions/`: one decision record per call a later contributor might
  question. Read [0001](docs/decisions/0001-decision-records.md) for the format.
- `docs/map.md`: each module of `src/`, what it owns, its invariants and the
  decision records behind it.
- `docs/lessons.md`: each bug an agent shipped, and the rule or test that now
  catches it.
- `.agents/skills/`: the skills any agent can load. `.claude/skills/` links to
  them.

## Plugins

Claude Code reads `.claude/settings.json`, which names the superpowers plugin
for brainstorming, plans, test-driven development and debugging. Naming it turns
it on but does not download it, so install it once on your machine with
`/plugin install superpowers@claude-plugins-official`.

## Hooks

Claude Code runs the gate as a Stop hook that `.claude/settings.json` names.
Codex CLI runs hooks too, from a `.codex/hooks.json` you have reviewed and
trusted, but this repository ships none
([Codex hooks](https://developers.openai.com/codex/hooks), checked 2026-10-30).
So for Codex, as for any tool without a Stop hook here, the git pre-commit hook
in `.githooks/` and CI are the only gate: turn the hook on with
`git config core.hooksPath .githooks`, and run `scripts/check.sh` yourself
before you say done, because the hook skips commits that touch no Rust code,
other compile input or Cargo file.
