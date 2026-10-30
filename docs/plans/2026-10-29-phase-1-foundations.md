# Phase 1: Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build phase 1 of Phyllon as the approved design describes: the
repository's rules and files, the gate in hooks and CI, the GitHub settings, a
skeleton binary with its compose and Quadlet stack, the branded web UI shell,
five skills with the map, and a signed, attested `v0.1.0`.

**Architecture:** One Rust package, `phyllon`, serves the web UI shell and the
health routes through axum, renders HTML with askama and reaches PostgreSQL
through sqlx. Caddy fronts it in a compose stack that runs unchanged under
Docker and rootless Podman, with Quadlet units beside it. Every rule lives in
one script or workflow that hooks and CI both call.

**Tech Stack:** Rust 1.99.1 (edition 2024), axum, askama, sqlx (postgres, no
TLS), tokio, clap, serde with toml, tower-http, thiserror, tracing; PostgreSQL
18 with pgvector; Caddy 2.11; GitHub Actions; release-plz; cosign; Playwright
with axe-core; prettier and markdownlint-cli2.

**Spec:**
[docs/specs/2026-10-29-phase-1-foundations-design.md](../specs/2026-10-29-phase-1-foundations-design.md),
which builds on [the high-level design](../specs/2026-10-29-phyllon-design.md).
Read both before the first task.

## Global Constraints

- Every change lands through a pull request and a squash merge. The pull request
  title is a conventional commit of at most 72 characters, because it becomes
  the commit on `main`.
- Every commit carries `Signed-off-by: Mika Böhme <mika@familieboehme.com>`, and
  an agent's commit also carries
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Mika's approval to
  execute this plan is the instruction to make each task's commits with that
  sign-off.
- Pushing to github.com needs Mika's security key. Only the main session pushes,
  and only after asking Mika in the question dialog; a subagent commits locally
  and never pushes.
- One concern per pull request, about 400 changed lines at most, not counting
  lockfiles, generated files and vendored text (license texts, the code of
  conduct, fonts).
- A new dependency (crate, npm package, action, image) takes the newest release
  that is at least 7 days old. Actions are pinned by commit SHA and images by
  digest, each with the version in a trailing comment.
- No `unsafe`, `unwrap`, `expect`, `panic!`, `todo!` or unchecked indexing
  outside tests. SQL goes only through sqlx with bound parameters.
- Tests never touch the network. A test that needs PostgreSQL is
  `#[ignore = "needs PostgreSQL"]` and runs in CI's `integration` job, which
  reads the standard `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE`
  variables.
- Markdown goes through prettier and then markdownlint-cli2 with the
  repository's configs. No em dashes, American spelling, sentence-case headings
  below the title, emoji only as heading labels.
- Names: package and binary `phyllon`; image `ghcr.io/nemesis398/phyllon`; port
  8080 inside the Phyllon container, 8080 and 8443 inside the Caddy container;
  database `phyllon`; roles `postgres` (bootstrap), `phyllon_owner` and
  `phyllon_runtime`; secret files `secrets/db_superuser_password`,
  `secrets/db_owner_password` and `secrets/db_runtime_password`; aliases
  `security@phyllon.de` and `conduct@phyllon.de`.
- License: `AGPL-3.0-or-later` for the code (the "or any later version" form the
  FSF recommends; confirmed by Mika on 2026-10-29).
- Releases: the first is `v0.1.0`; every release before 1.0 is a GitHub
  pre-release; images are tagged with the exact version and the minor line
  (`0.1.0` and `0.1`), never `latest` before 1.0; a breaking change or any
  database migration raises the minor number.
- Release provenance reaches SLSA v1.0 Build Level 3 (decided by Mika on
  2026-10-30): every release artifact is built and attested inside one reusable
  workflow, `.github/workflows/build.yml`, which `release.yml` calls, so the
  calling workflow cannot touch the build or the signing. Verification pins that
  workflow with
  `--signer-workflow nemesis398/phyllon/.github/workflows/build.yml`, and the
  cosign identity is
  `https://github.com/nemesis398/phyllon/.github/workflows/build.yml@refs/heads/main`.
- Every job that has steps in `build.yml` and `release.yml` starts with
  `step-security/harden-runner`, pinned by SHA like every action, with
  `egress-policy: block` and an `allowed-endpoints` list of exactly the hosts
  the job needs (Mika, 2026-10-30). The other workflows do not use it.
- Security headers, exact values:
  <!-- markdownlint-disable-next-line MD013 -->
  `Content-Security-Policy: default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`,
  `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
  `Strict-Transport-Security: max-age=31536000` (no `includeSubDomains`, because
  a deployer's other subdomains are not Phyllon's to decide),
  `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()`.

## Review Focus

1. A secret file that ends in `\n` or `\r\n`, which is what `openssl rand` and
   Windows editors write: the secret is the content without the line ending.
   Test in Task 8.
2. A PostgreSQL that accepts the connection and never answers: `/readyz` answers
   503 within 2 seconds instead of hanging. Test in Task 9.
3. A server that accepts the healthcheck's connection and never answers, or
   answers something that is not HTTP: `phyllon healthcheck` exits 1 within 3
   seconds. Test in Task 10.
4. `listen = "0.0.0.0:8080"` or `"[::]:8080"`: the healthcheck probes
   `127.0.0.1` or `[::1]` on the same port. Test in Task 10.
5. `HEAD /healthz` and requests for unknown paths: a 200 for the HEAD, the
   branded 404 page for the unknown path, the security headers on both, and
   never a panic. Test in Task 9.

## How every task ends

Each task works on its own branch, `p1/NN-slug`, cut from an up-to-date `main`,
and ends the same way:

1. Run `scripts/check.sh` (from Task 4 on) and the Markdown checks (from Task 1
   on): `npx prettier --check .` and `npx markdownlint-cli2`. Both pass.
2. Commit with the sign-off and the trailer from the Global Constraints.
3. The main session asks Mika for the key, pushes, and opens the pull request
   with `gh pr create --milestone "M1 Foundations"`, so that GitHub files it
   under the phase. The body ends with what ran, what did not, and what the
   author is unsure of.
4. CI is green (from Task 6 on). The main session asks Mika in the question
   dialog and, on Mika's yes, merges with `gh pr merge --squash`.
5. Tick the task in this file and in the step list of its Plane item, with the
   merge commit as evidence.

---

## Part 1: The rules first (PHY-13, PHY-14)

### Task 1: Land the design, the plan and the Markdown rule

**Files:**

- Add: `docs/specs/2026-10-29-phase-1-foundations-design.md`,
  `docs/plans/2026-10-29-phase-1-foundations.md` (both exist, uncommitted)
- Modify: the seven Markdown files already reformatted in the working tree
- Create: `.prettierrc.yaml`, `.markdownlint-cli2.yaml`, `.prettierignore`,
  `package.json`, `package-lock.json`

**Interfaces:**

- Produces: `npx prettier --check .` and `npx markdownlint-cli2` as the Markdown
  check every later task runs.

- [x] **Step 1: Write the configs.** `.prettierrc.yaml` sets `proseWrap: always`
      and `printWidth: 80`. `.markdownlint-cli2.yaml` sets `MD013` to
      `line_length: 80`, `tables: false`, `code_blocks: false`; `MD024` to
      `siblings_only: true`; and ignores `.superpowers/**`, `node_modules/**`
      and `target/**`. `.prettierignore` lists the same three paths.
      `package.json` at the root is `"private": true` with `prettier` and
      `markdownlint-cli2` as exact-version devDependencies; Task 16 adds the
      browser test packages to the same file, so all Node tooling shares one
      lockfile (the design put that lockfile in `tests/browser/`; one lockfile
      for both tools is simpler, and it is still the only Node code) (the
      versions in nvim's Mason today are prettier 3.9.10 and markdownlint-cli2
      0.23.3; take them if they pass the 7-day rule).
- [x] **Step 2: Run the checks.** Run
      `npm ci && npx prettier --check . && npx markdownlint-cli2`. Expected:
      prettier passes; markdownlint reports at most the lines that hold one
      unbreakable inline code span or URL.
- [x] **Step 3: Fix what remains** by rewording the sentence around the span
      (expected in `docs/research/prior-art.md`, the `AnswerTest` signature
      line). Run the checks again; both pass.
- [x] **Step 4: Ship** (see "How every task ends"). Title:
      `docs: add the phase 1 design and plan, and format the docs`.

Done: merged in e853d45 (#1) on 2026-10-29.

### Task 2: Repository files

**Files:**

- Create: `README.md`, `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`,
  `CODE_OF_CONDUCT.md`, `.github/ISSUE_TEMPLATE/bug.yml`,
  `.github/ISSUE_TEMPLATE/proposal.yml`, `.github/ISSUE_TEMPLATE/config.yml`,
  `.github/pull_request_template.md`

**Interfaces:**

- Consumes: the Markdown check from Task 1.
- Produces: the sign-off rule and the hook setup line in CONTRIBUTING, which
  Tasks 4 and 6 implement.

- [x] **Step 1: Mika confirms the aliases.** Mika creates `security@phyllon.de`
      and `conduct@phyllon.de` as forwarding aliases and confirms that a test
      mail to each arrives. SECURITY and CODE_OF_CONDUCT are not merged before
      that.
- [x] **Step 2: Vendor the two texts unchanged.** `LICENSE` is
      <https://www.gnu.org/licenses/agpl-3.0.txt>. `CODE_OF_CONDUCT.md` is
      Contributor Covenant 3.0 from
      <https://www.contributor-covenant.org/version/3/0/code_of_conduct/>, with
      `conduct@phyllon.de` as the reporting contact. Add both paths to
      `.prettierignore`, so the formatter leaves the vendored text alone.
- [x] **Step 3: Write the README.** Contents, in order: the lockup
      (`brand/lockup.svg`); what Phyllon is, in two sentences from the design's
      intent; status ("a skeleton, nothing to use yet"); the principle ("decide
      in code, phrase in the model"); the quickstart, as a link to
      `docs/install.md`, which Task 14 writes; links to the design, the roadmap,
      CONTRIBUTING and SECURITY; badges for CI, Scorecard and the license, and
      no others. License line: AGPL-3.0-or-later.
- [x] **Step 4: Write CONTRIBUTING.** Sections: the sign-off (what the DCO
      certifies, `git commit -s`, and the agent rule from the design word for
      word: an agent adds the sign-off of the person who directs it, only on
      that person's instruction, and is credited with a `Co-Authored-By:`
      trailer); pull requests (one concern, about 400 lines, squash merge, a
      conventional-commit title); turning on the hooks
      (`git config core.hooksPath .githooks`); the gate (`scripts/check.sh`);
      AI-assisted contributions (welcome under the same rules; the pull request
      says what ran, what did not, and what is unsure).
- [x] **Step 5: Write SECURITY.** Channels: GitHub private vulnerability
      reporting first, `security@phyllon.de` as the fallback. Supported
      versions: the latest release only, until 1.0. First answer within 14 days.
      Coordinated disclosure: a fix and an advisory together, crediting the
      reporter unless they decline.
- [x] **Step 6: Write the GitHub templates.** `bug.yml` asks for the version,
      the install path (Docker, Podman, Quadlet), the steps, the expected and
      the actual result. `proposal.yml` asks for the problem and who has it,
      before any solution. `config.yml` turns blank issues off and links
      security reports to the private reporting page. The pull request template
      asks for the sign-off, what ran, what did not, and what the author is
      unsure of.
- [x] **Step 7: Ship.** Title:
      `docs: add the readme, license, contributing, security and conduct files`.

Done: merged in f607047 (#2) on 2026-10-29. Mika confirmed both aliases on
2026-10-29.

### Task 3: Agent rules, decision records and lessons

**Files:**

- Create: `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`,
  `docs/decisions/0001-decision-records.md`, `docs/lessons.md`

**Interfaces:**

- Produces: `.claude/settings.json`, which Task 5 extends with hooks; the
  decision-record format that Tasks 13, 18, 19 and 21 use.

- [x] **Step 1: Write AGENTS.md.** The fifteen rules from section 8 of
      `docs/research/engineering-quality.md`, each as one or two sentences with
      its reason in one clause, adapted: rule 1 names `scripts/check.sh`; rule 3
      lists the gate's files (`Cargo.toml` `[lints]`, `clippy.toml`,
      `deny.toml`, `rust-toolchain.toml`, `.github/workflows/`, `.githooks/`,
      `.claude/settings.json`, `scripts/check.sh`) as changeable only with the
      maintainer's explicit approval in the pull request; rule 9 says squash
      merges and conventional titles; a new rule 16 holds the sign-off rule.
      Then where things live: `docs/specs/`, `docs/plans/`, `docs/decisions/`,
      `docs/map.md`, `docs/lessons.md`, `.agents/skills/`.
- [x] **Step 2: Write CLAUDE.md** with the single line `@AGENTS.md`.
- [x] **Step 3: Write `.claude/settings.json`** naming the superpowers plugin
      through `extraKnownMarketplaces` and `enabledPlugins`. Check the key names
      against the Claude Code settings docs before writing them.
- [x] **Step 4: Write the first decision record.** `0001-decision-records.md`:
      one file per decision, `NNNN-slug.md`, with Context, Options, the
      comparison on the conscience's five dials (granularity, redundancy,
      coupling, retention, flow control) as a table, Decision, and Consequences;
      status `accepted` or `superseded by NNNN`.
- [x] **Step 5: Write `docs/lessons.md`** with its format only: per entry the
      bug, the rule or test that now catches it, and the pull request.
- [x] **Step 6: Ship.** Title:
      `docs: add the agent rules, decision records and lessons`.

Done: merged in d1d7a1c (#3) on 2026-10-30.

## Part 2: The gate (PHY-15)

### Task 4: The package, the toolchain and the gate script

**Files:**

- Create: `Cargo.toml`, `Cargo.lock`, `src/main.rs`, `src/lib.rs`,
  `rust-toolchain.toml`, `clippy.toml`, `deny.toml`, `scripts/check.sh`,
  `.githooks/pre-commit`

**Interfaces:**

- Produces: `scripts/check.sh` (exit 0 when the gate passes, non-zero with the
  failing step's output otherwise), which Tasks 5 and 6 call; the empty library
  crate `phyllon` that Part 4 fills.

- [x] **Step 1: Pin the toolchain.** `rust-toolchain.toml`: `channel = "1.99.1"`
      (or the newest stable at least 7 days old), components `rustfmt` and
      `clippy`.
- [x] **Step 2: Write `Cargo.toml`.** `name = "phyllon"`, `version = "0.0.0"`
      (Task 21 sets `0.1.0`), `edition = "2024"`, `rust-version` equal to the
      pinned toolchain, `license = "AGPL-3.0-or-later"`, `repository`,
      `publish = false`, and the lint baseline from section 3.5 of the
      engineering research under `[lints.rust]` and `[lints.clippy]`
      (package-level tables, since there is no workspace). `src/main.rs` is
      `fn main() {}`; `src/lib.rs` is empty.
- [x] **Step 3: Write `clippy.toml`** with `allow-unwrap-in-tests`,
      `allow-expect-in-tests`, `allow-panic-in-tests` and
      `allow-indexing-slicing-in-tests` set to `true`.
- [x] **Step 4: Write `deny.toml`.** Sources: crates.io only, unknown registries
      and git denied. Licenses allowed: `MIT`, `Apache-2.0`,
      `Apache-2.0 WITH LLVM-exception`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`,
      `Zlib`, `Unicode-3.0`, `MPL-2.0`, `CC0-1.0` and `AGPL-3.0-or-later`. Bans:
      `openssl` and `openssl-sys` denied; multiple versions warn.
- [x] **Step 5: Write `scripts/check.sh`** (`set -euo pipefail`), which runs in
      order and prints each step's name: `cargo fmt --all --check`;
      `cargo clippy --all-targets --locked -- -D warnings`;
      `cargo nextest run --locked --no-tests=pass`; `cargo test --doc --locked`;
      `cargo shear`; `cargo deny check bans licenses sources`. A missing tool
      fails with its install command.
- [x] **Step 6: Write `.githooks/pre-commit`,** which runs `scripts/check.sh`
      only when the staged files include `*.rs`, `Cargo.toml`, `Cargo.lock`,
      `clippy.toml`, `deny.toml` or `rust-toolchain.toml`, so a docs-only commit
      does not wait for the gate.
- [x] **Step 7: Run the gate.** Run `scripts/check.sh`. Expected: every step
      passes, exit 0.
- [x] **Step 8: Prove the gate bites.** Add
      `pub fn f() -> u8 { "1".parse().unwrap() }` to `src/lib.rs` and run
      `scripts/check.sh`. Expected: exit non-zero, output names
      `clippy::unwrap_used`. Remove the line.
- [x] **Step 9: Ship.** Title:
      `build: add the package, the toolchain pin and the gate script`.

Done: merged in fd46d5c (#4) on 2026-10-30.

### Task 5: Claude Code hooks

**Files:**

- Create: `scripts/hooks/format-edited.sh`, `scripts/hooks/stop-gate.sh`,
  `scripts/hooks/test.sh`
- Modify: `.claude/settings.json`

**Interfaces:**

- Consumes: `scripts/check.sh` from Task 4.
- Produces: `PHYLLON_GATE_CMD`, an environment variable that replaces
  `scripts/check.sh` in `stop-gate.sh`, used only by `scripts/hooks/test.sh`.

- [x] **Step 1: Read the hook docs** for the pinned Claude Code version: the
      JSON a `PostToolUse` and a `Stop` hook receive on stdin
      (`tool_input.file_path`, `stop_hook_active`), and what exit code 2 does
      for each.
- [x] **Step 2: Write the failing tests** in `scripts/hooks/test.sh`, each one a
      function that feeds a JSON document to `stop-gate.sh` in a temporary git
      repository and checks the exit code: `gate_green_lets_the_agent_stop`
      (fake gate exits 0, hook exits 0 and writes `target/.gate-green`);
      `gate_red_blocks_the_stop` (fake gate exits 1 with "boom", hook exits 2
      and stderr contains "boom"); `unchanged_files_skip_the_gate` (second run
      after a green run does not call the fake gate, which would fail);
      `a_repeated_red_stop_is_let_through` (`stop_hook_active: true` and the
      same fingerprint as the last red run: exit 0, stderr says the gate is
      still red).
- [x] **Step 3: Run them.** Run `scripts/hooks/test.sh`. Expected: all four
      fail, because `stop-gate.sh` does not exist.
- [x] **Step 4: Write `stop-gate.sh`.** The fingerprint is the SHA-256 over the
      contents of every tracked and untracked file matching `*.rs`,
      `Cargo.toml`, `Cargo.lock`, `*.toml` at the root and
      `.github/workflows/*`. A match with `target/.gate-green` exits 0;
      otherwise it runs the gate, writes the fingerprint to `target/.gate-green`
      on success or `target/.gate-red` on failure, and exits 2 with the output
      on stderr.
- [x] **Step 5: Write `format-edited.sh`,** which runs `rustfmt --edition 2024`
      on an edited `*.rs` file and always exits 0.
- [x] **Step 6: Register both** in `.claude/settings.json`: `PostToolUse` with
      the matcher `Edit|MultiEdit|Write`, and `Stop`.
- [x] **Step 7: Run the tests.** Run `scripts/hooks/test.sh`. Expected: four
      passes.
- [x] **Step 8: Ship.** Title: `build: run the gate as a Claude Code stop hook`.

Done: merged in cd4d0e0 (#5) on 2026-10-30.

### Task 6: CI workflows and Dependabot

**Files:**

- Create: `.github/workflows/ci.yml`, `.github/workflows/workflows.yml`,
  `.github/workflows/nightly.yml`, `.github/workflows/scorecard.yml`,
  `.github/dependabot.yml`, `scripts/ci/check-pr-title.sh`,
  `scripts/ci/check-signoff.sh`, `scripts/ci/test.sh`

**Interfaces:**

- Consumes: `scripts/check.sh`, the Markdown check.
- Produces: the required check names `gate`, `integration (17)`,
  `integration (18)`, `pr-title`, `sign-off`, `markdown`, `scripts` and
  `dependency-review`, which the ruleset in Task 7 names exactly; the `scripts`
  job, which later tasks extend with their script tests. Every job of `ci.yml`
  and the `pr-title` job of `pr-title.yml` is a required check, and a task that
  adds a job adds its name to `scripts/github-settings.sh`.

- [x] **Step 1: Write the failing script tests** in `scripts/ci/test.sh`.
      Titles: `feat(web): add the shell` passes;
      `build(deps): bump axum from 0.8.4 to 0.8.5` passes; `Update stuff` fails;
      `feat:` fails; a valid title of 73 characters fails. Sign-off, in a
      temporary repository: a commit whose `Signed-off-by:` matches its author
      passes; a commit without one fails and the output names its SHA; a
      sign-off for a different person than the author fails; a commit by
      `dependabot[bot]` passes without one.
- [x] **Step 2: Run them.** Run `scripts/ci/test.sh`. Expected: every case
      fails, because the scripts do not exist.
- [x] **Step 3: Write `check-pr-title.sh TITLE`,** which accepts
      <!-- markdownlint-disable-next-line MD013 -->
      `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9-]+\))?!?: \S.*$`
      up to 72 characters.
- [x] **Step 4: Write `check-signoff.sh BASE HEAD`,** which checks every commit
      in `BASE..HEAD` for a `Signed-off-by:` line equal to
      `<author name> <author email>`, exempting the author `dependabot[bot]`.
- [x] **Step 5: Run the script tests.** Run `scripts/ci/test.sh`. Expected: all
      pass.
- [x] **Step 6: Write `ci.yml`.** Triggers `pull_request` and `push` to `main`;
      `permissions: {}` at the top; `actions/checkout` with
      `persist-credentials: false` in every job. Jobs: `gate` (installs nextest,
      shear and deny with a pinned `taiki-e/install-action`, caches with a
      pinned `Swatinem/rust-cache`, runs `scripts/check.sh`,
      `cargo deny check advisories` and `cargo doc --no-deps --locked` with
      `RUSTDOCFLAGS=-D warnings`); `integration` (matrix 17 and 18, a
      `pgvector/pgvector` service per version pinned by digest,
      `cargo nextest run --locked --run-ignored only`); `pr-title` and
      `sign-off` (pull requests only; the title passes through an `env:`
      variable, never `${{ }}` inside `run:`); `markdown` (`npm ci`, the two
      Markdown checks); `scripts` (`shellcheck` on `scripts/**/*.sh` and
      `.githooks/*`, then `scripts/ci/test.sh` and `scripts/hooks/test.sh`);
      `dependency-review` (pull requests only, `permissions: contents: read`; a
      pinned `actions/dependency-review-action` with `fail-on-severity: low` and
      an `allow-licenses` list equal to the one in `deny.toml`: MIT, Apache-2.0,
      Apache-2.0 WITH LLVM-exception, BSD-2-Clause, BSD-3-Clause, ISC, Zlib,
      Unicode-3.0, MPL-2.0, CC0-1.0 and AGPL-3.0-or-later). It covers what
      `cargo deny` does not, the npm tooling and the GitHub Actions (Mika,
      2026-10-30).
- [x] **Step 7: Write the other workflows.** `workflows.yml`: on pull requests
      touching `.github/**`, zizmor and actionlint, both pinned. `nightly.yml`:
      daily at 03:17 UTC, `cargo deny check advisories`. `scorecard.yml`:
      weekly, the OpenSSF Scorecard action with `publish_results: true` and only
      the permissions its README names.
- [x] **Step 8: Write `dependabot.yml`.** Ecosystems `cargo`, `github-actions`,
      `docker`, `docker-compose`, `npm` and `rust-toolchain`, all at `/`,
      weekly, with `cooldown: default-days: 7` and commit prefixes `build(deps)`
      (and `ci(deps)` for actions), so Dependabot's titles pass `pr-title`.
- [x] **Step 9: Lint the workflows locally.** Run `actionlint` and
      `zizmor .github/workflows`. Expected: no findings.
- [x] **Step 10: Ship.** Title:
      `ci: run the gate, the title and sign-off checks on every pull request`.
      Expected on the pull request: all jobs green.

Done: merged in 8b60a3b (#7) on 2026-10-30.

## Part 3: GitHub settings (PHY-12)

### Task 7: Repository settings, the ruleset and the redirect

**Files:**

- Create: `scripts/github-settings.sh`, `brand/social-preview.svg`,
  `brand/social-preview.png`

**Interfaces:**

- Consumes: the check names from Task 6.
- Produces: `scripts/github-settings.sh audit`, which exits 0 when every setting
  matches and lists each drift otherwise.

- [x] **Step 1: Write the expected settings once,** as a table inside
      `scripts/github-settings.sh` that both `apply` and `audit` read: homepage
      `https://phyllon.de`; Discussions on; squash merges only, with the commit
      title from the pull request title and the message from the commit messages
      (so sign-offs reach `main`); delete branches on merge; private
      vulnerability reporting on; secret scanning and push protection on;
      Dependabot alerts and security updates on; CodeQL default setup
      configured; immutable releases on; workflow permissions read-only, no pull
      request approvals by Actions; fork pull request approval
      `all_external_contributors`; one ruleset on `main` that requires a pull
      request (zero approvals, squash only), the eight checks from Task 6,
      linear history and signed commits (Mika, 2026-10-30; GitHub signs squash
      merges and Dependabot's commits, so nothing legitimate breaks), and blocks
      force pushes and deletion, with no bypass actors.
- [x] **Step 2: Run the audit before applying.** Run
      `scripts/github-settings.sh audit`. Expected: exit 1, listing what differs
      today (homepage, Discussions, merge methods, reporting, Dependabot,
      CodeQL, immutable releases, fork approval, ruleset).
- [x] **Step 3: Apply, after Mika confirms.** These change a public repository:
      show Mika the list from Step 2 in the question dialog, then run
      `scripts/github-settings.sh apply`.
- [x] **Step 4: Run the audit again.** Expected: exit 0. Also check the
      maintainer account: `gh api user --jq .two_factor_authentication` prints
      `true`.
- [x] **Step 5: Build the social preview** as a 1280 by 640 SVG from the lockup
      and the palette, rendered to PNG with `rsvg-convert`. Mika uploads the PNG
      in the repository settings, since the API cannot.
- [x] **Step 6: Mika sets the redirect.** Mika points `phyllon.de` at
      `https://github.com/nemesis398/phyllon` with an HTTPS redirect. Check:
      `curl -sI https://phyllon.de` shows a 301 or 308 with that `location`.
- [x] **Step 7: Ship** the script and the preview. Title:
      `chore: keep the GitHub settings in a script`.

Done: merged in ff2db67 (#11) on 2026-10-30.

## Part 4: The skeleton (PHY-16)

### Task 8: Configuration

**Files:**

- Create: `src/config.rs`, `tests/config.rs`
- Modify: `src/lib.rs`, `Cargo.toml` (serde, toml, thiserror)

**Interfaces:**

- Produces:

```rust
pub struct Config { pub listen: SocketAddr, pub public_url: String, pub source_url: Option<String>, pub database: DatabaseConfig }
pub struct DatabaseConfig { pub host: String, pub port: u16, pub name: String, pub user: String, pub password_file: PathBuf }
pub struct Secret(/* private */ String);           // Debug prints "Secret([redacted])"
impl Secret { pub fn expose(&self) -> &str }
impl Config { pub fn load(path: &Path) -> Result<Config, ConfigError> }
impl DatabaseConfig { pub fn password(&self) -> Result<Secret, ConfigError> }
pub enum ConfigError { Read { path: PathBuf, source: std::io::Error }, Parse(toml::de::Error), PublicUrl(String), Secret { key: &'static str, path: PathBuf, source: std::io::Error } }
```

Defaults: `listen = "0.0.0.0:8080"`, `database.port = 5432`. Every table uses
`deny_unknown_fields`.

- [x] **Step 1: Write the failing tests** in `tests/config.rs`:
      `loads_a_minimal_config` (only `public_url` and
      `database.{host,name,user,password_file}` given: `listen` is
      `0.0.0.0:8080`, port 5432); `rejects_an_unknown_key` (`listn = "…"`:
      `ConfigError::Parse` whose message contains "unknown field `listn`");
      `rejects_a_public_url_without_an_http_scheme` (`"phyllon.example"`:
      `ConfigError::PublicUrl`); `reads_the_password_without_its_line_ending`
      (files holding `s3cret\n` and `s3cret\r\n`: `expose()` is `"s3cret"` for
      both); `a_password_error_names_the_key_not_the_content` (missing file: the
      `Display` text contains `database.password_file` and the path);
      `secret_debug_is_redacted`
      (`format!("{:?}", secret) == "Secret([redacted])"`).
- [x] **Step 2: Run them.** Run `cargo nextest run --test config`. Expected:
      compile errors, because the module does not exist.
- [x] **Step 3: Implement `src/config.rs`** to the interface above. `public_url`
      must start with `https://` or `http://`. `password()` strips one trailing
      `\n` or `\r\n`, nothing else.
- [x] **Step 4: Run the tests.** Expected: six passes. Then run
      `scripts/check.sh`; it passes.
- [x] **Step 5: Ship.** Title:
      `feat(config): load the TOML config with secrets from files`.

Done: merged in 96fb377 (#14) on 2026-10-30.

### Task 9: Database readiness and the HTTP layer

**Files:**

- Create: `src/db.rs`, `src/http/mod.rs`, `src/http/headers.rs`, `tests/http.rs`
- Modify: `src/lib.rs`, `Cargo.toml` (axum, tokio, sqlx with `runtime-tokio` and
  `postgres` and no TLS feature, tower-http with `set-header` and `catch-panic`,
  tracing)

**Interfaces:**

- Consumes: `DatabaseConfig`, `Secret` from Task 8.
- Produces:

```rust
// src/db.rs
pub fn pool(cfg: &DatabaseConfig, password: &Secret) -> sqlx::PgPool   // connect_lazy_with; acquire timeout 2 s
pub async fn ready(pool: &sqlx::PgPool) -> bool                        // acquire + ping, all within 2 s
// src/http/mod.rs
#[derive(Clone)] pub struct AppState { pub pool: sqlx::PgPool, pub build: BuildInfo, pub source_url: String }
#[derive(Clone, Copy)] pub struct BuildInfo { pub version: &'static str, pub commit: Option<&'static str> }
impl BuildInfo { pub fn current() -> BuildInfo }   // CARGO_PKG_VERSION, option_env!("PHYLLON_GIT_COMMIT")
pub fn router(state: AppState) -> axum::Router      // all routes, a fallback, then with_security_layers
pub fn with_security_layers(router: axum::Router) -> axum::Router   // headers + catch-panic
pub enum AppError { Internal }                     // the one error type; IntoResponse gives a generic 500
pub fn source_url(configured: Option<&str>, build: &BuildInfo) -> String
// src/http/headers.rs
pub const SECURITY_HEADERS: [(&str, &str); 5];      // the exact values from the Global Constraints
```

`source_url`: the configured value if set; else
`https://github.com/nemesis398/phyllon/tree/<commit>` when the build has a
commit; else `https://github.com/nemesis398/phyllon`. `serve` computes it once
into `AppState`. `ready` uses sqlx's `ping` rather than a `SELECT 1` string; it
does the same job and keeps the offline query data out of phase 1, until phase
2's first query macro needs it.

- [x] **Step 1: Write the failing tests** in `tests/http.rs`, driving the router
      with `tower::ServiceExt::oneshot` and a pool pointed at `127.0.0.1:1`:
      `healthz_answers_200`; `head_healthz_answers_200`;
      `readyz_is_503_when_the_database_is_unreachable`;
      `readyz_is_503_within_2s_when_the_database_hangs` (a `TcpListener` that
      accepts and never writes; assert under 3 s);
      `every_response_carries_the_security_headers` (for `/healthz`, `/readyz`
      and `/no-such-page`, each of the five headers with its exact value);
      `an_unknown_path_is_404`;
      `a_panicking_handler_returns_a_generic_500_and_the_server_keeps_serving`
      (`with_security_layers` around a router with `/boom` that panics with
      "boom" and `/ok`: status 500, the body does not contain "boom", the
      headers are present, and `/ok` then answers 200);
      `source_url_prefers_the_config`;
      `source_url_without_a_commit_points_at_the_repository`; and, ignored,
      `readyz_is_200_with_a_database`.
- [x] **Step 2: Run them.** Run `cargo nextest run --test http`. Expected:
      compile errors.
- [x] **Step 3: Implement `db.rs`, `headers.rs` and `http/mod.rs`** to the
      interface. The fallback answers 404 and `AppError` a 500, both with a
      plain body for now; Task 15 replaces them with the branded pages.
- [x] **Step 4: Run the tests.** Expected: nine passes, one ignored. Run the
      ignored one against a local PostgreSQL with
      `cargo nextest run --test http --run-ignored only`; it passes. Then
      `scripts/check.sh`.
- [x] **Step 5: Ship.** Title:
      `feat(http): serve health and readiness with the security headers`.

Done: merged in c4d2cb3 (#15) on 2026-10-30.

### Task 10: The command line, `serve` and `healthcheck`

**Files:**

- Create: `src/cli.rs`, `tests/cli.rs`
- Modify: `src/main.rs`, `src/lib.rs`, `Cargo.toml` (clap with `derive` and
  `env`, tracing-subscriber)

**Interfaces:**

- Consumes: `Config::load`, `db::pool`, `http::router`, `AppState`, `BuildInfo`.
- Produces:

```rust
pub fn run() -> std::process::ExitCode                 // parses args; `serve` and `healthcheck`, both with --config / PHYLLON_CONFIG; --version
pub fn probe(addr: SocketAddr, timeout: Duration) -> Result<(), ProbeError>   // blocking, std::net only
pub fn probe_addr(listen: SocketAddr) -> SocketAddr    // 0.0.0.0 -> 127.0.0.1, [::] -> [::1], others unchanged
```

`probe` writes
`GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n` and
succeeds only when the status line starts with `HTTP/1.1 200`. `healthcheck`
probes `probe_addr(config.listen)` with a 3-second timeout. `serve` logs to
stderr and shuts down cleanly on SIGTERM and Ctrl-C.

- [x] **Step 1: Write the failing tests** in `tests/cli.rs`:
      `probe_succeeds_against_a_running_server`;
      `probe_fails_when_nothing_listens`;
      `probe_fails_within_3s_when_the_server_never_answers` (assert under 4 s);
      `probe_fails_on_an_answer_that_is_not_http` (the server writes
      `garbage\r\n`); `probe_addr_maps_unspecified_addresses_to_loopback`
      (`0.0.0.0:8080` to `127.0.0.1:8080`, `[::]:8080` to `[::1]:8080`,
      `10.0.0.5:9000` unchanged); `serve_and_healthcheck_work_end_to_end` (runs
      `env!("CARGO_BIN_EXE_phyllon")` with a temporary config on a free port and
      the database at `127.0.0.1:1`, waits for the port, runs
      `phyllon healthcheck` with the same config, expects exit 0, then stops the
      server).
- [x] **Step 2: Run them.** Expected: compile errors.
- [x] **Step 3: Implement `cli.rs` and `main.rs`**
      (`fn main() -> ExitCode { phyllon::cli::run() }`).
- [x] **Step 4: Run the tests and the gate.** Expected: six passes;
      `scripts/check.sh` passes.
- [x] **Step 5: Ship.** Title:
      `feat(cli): add the serve and healthcheck commands`.

Done: merged in 2559866 (#17) on 2026-10-30.

## Part 5: Running it (PHY-16)

### Task 11: The container image

**Files:**

- Create: `Dockerfile`, `.dockerignore`

**Interfaces:**

- Produces: an image whose entrypoint is `/usr/local/bin/phyllon` with the
  command `serve`, running as `nonroot`; the build argument
  `PHYLLON_GIT_COMMIT`.

- [x] **Step 1: Write the Dockerfile.** Builder: `rust:1.99.1-alpine` pinned by
      digest, `apk add musl-dev`, `cargo install --locked cargo-auditable` at a
      pinned version (the newest one at least 7 days old, matching the
      Dependabot cooldown), then `cargo auditable build --release --locked`, so
      the binary carries its crate list (Mika, 2026-10-30), with
      `PHYLLON_GIT_COMMIT` passed as a build argument and environment variable.
      Final stage: `gcr.io/distroless/static-debian13:nonroot` pinned by digest,
      the binary only, `EXPOSE 8080`. Keep the base image names in one place at
      the top, since phase 2 may move to `distroless/cc`. `.dockerignore`
      excludes `target/`, `.git/`, `node_modules/`, `.superpowers/` and
      `secrets/`.
- [x] **Step 2: Build and inspect.** Run
      <!-- markdownlint-disable-next-line MD013 -->
      `docker build --build-arg PHYLLON_GIT_COMMIT=$(git rev-parse HEAD) -t phyllon:dev .`,
      then `docker run --rm phyllon:dev --version` (prints `phyllon 0.0.0`) and
      `docker image inspect phyllon:dev --format '{{.Config.User}}'` (prints
      `nonroot` or `65532`).
- [x] **Step 3: Confirm the binary is static.** Run
      `docker run --rm --entrypoint '' phyllon:dev /usr/local/bin/phyllon --version`
      on the distroless base, which has no libc; it prints the version.
- [x] **Step 4: Confirm the binary lists its crates.** Copy it out of the image
      with `docker create` and `docker cp`, then run
      `readelf -S phyllon | grep .dep-v0` (or `objdump -h`). Expected: the
      `.dep-v0` section is there. Phase 1 stops at the section; a scanner reads
      it from Task 21 on.
- [x] **Step 5: Ship.** Title: `build: build a static image on distroless`.

Done: merged in 66c7a5a (#19) on 2026-10-30.

### Task 12: The compose stack and its posture

**Files:**

- Create: `compose.yaml`, `.env.example`, `deploy/Caddyfile`,
  `deploy/phyllon.toml`, `deploy/postgres/10-roles.sh`, `scripts/posture.sh`,
  `scripts/stack-test.sh`
- Modify: `.github/workflows/ci.yml` (a `stack-docker` job), `.gitignore`
  (`secrets/`, `.env`)

**Interfaces:**

- Consumes: the image from Task 11.
- Produces: `scripts/stack-test.sh ENGINE` (`docker` or `podman`), which brings
  the stack up from `.env.example`, runs every check below and tears it down;
  `scripts/posture.sh ENGINE PROJECT`, which exits 1 and lists each gap.

- [x] **Step 1: Write `compose.yaml`** with the three services, the two networks
      (`edge`, and `db` with `internal: true`) and the volumes `db-data` and
      `caddy-data`, as the design's table describes. `phyllon` uses
      `image: ${PHYLLON_IMAGE:-ghcr.io/nemesis398/phyllon:0.1}`,
      `PHYLLON_CONFIG=/etc/phyllon/phyllon.toml`, the runtime password file
      mounted read-only at `/run/secrets/db_runtime_password` (a `volumes:` bind
      mount with `:ro,z`, not compose `secrets:`; Mika, 2026-10-30), a
      healthcheck of `["CMD", "/usr/local/bin/phyllon", "healthcheck"]`, and
      `depends_on: db: condition: service_healthy`. `db` runs as `999:999` with
      `POSTGRES_DB=phyllon`, `POSTGRES_PASSWORD_FILE`,
      `POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256 --auth-local=scram-sha-256`,
      and `deploy/postgres/10-roles.sh` mounted into
      `/docker-entrypoint-initdb.d/`. `proxy` sits in the compose profile
      `proxy` and publishes `${HTTP_PORT:-80}:8080` and
      `${HTTPS_PORT:-443}:8443`. Every service gets `cap_drop: [ALL]`,
      `security_opt: [no-new-privileges:true]`, memory and pids limits, a
      healthcheck and a non-root user; `phyllon` also gets `read_only: true` and
      a tmpfs on `/tmp`.
- [x] **Step 2: Write `.env.example`:** `COMPOSE_PROFILES=proxy`,
      `PHYLLON_DOMAIN=localhost`, `HTTP_PORT=8080`, `HTTPS_PORT=8443`,
      `PHYLLON_IMAGE=ghcr.io/nemesis398/phyllon:0.1`.
- [x] **Step 3: Write `deploy/Caddyfile`.** Global options `http_port 8080`,
      `https_port 8443` and `auto_https disable_redirects`; an
      `http://{$PHYLLON_DOMAIN}` site that redirects to
      `https://{host}:{$HTTPS_PORT}{uri}`; a `{$PHYLLON_DOMAIN}` site with
      `reverse_proxy phyllon:8080`. Check in the Caddy docs that ACME challenges
      are still answered on `http_port` with redirects disabled, and record that
      page in the commit body.
- [x] **Step 4: Write `deploy/postgres/10-roles.sh`.** It reads the two
      passwords from `/run/secrets/`, passes them to `psql` as variables (`-v`)
      so quoting stays safe, and in the `phyllon` database creates the `vector`
      extension, `phyllon_owner` (owner of the database) and `phyllon_runtime`
      (`LOGIN`, `CONNECT`, `USAGE` on `public`, and default privileges
      `SELECT, INSERT, UPDATE, DELETE` on tables and `USAGE, SELECT` on
      sequences that `phyllon_owner` creates; no `CREATE`).
- [x] **Step 5: Write `scripts/posture.sh`.** For each container of the project,
      from `inspect`: not privileged; not on the host network; `CapDrop`
      includes `ALL`; `no-new-privileges` set; memory and pids limits set; a
      healthcheck defined; no mount of `docker.sock` or `podman.sock`; a
      non-root user; port bindings only on `proxy`; and for `phyllon` a
      read-only root.
- [x] **Step 6: Write `scripts/stack-test.sh`.** It creates the three secrets
      the way the install guide will (`mkdir -m 700 secrets`, then
      `(umask 222; openssl rand -base64 32 > secrets/<name>)` for each), copies
      `.env.example`, sets `PHYLLON_IMAGE` to a locally built image when given,
      runs `compose up -d --wait`, and checks:
      `curl -fsk https://localhost:8443/healthz` and `/readyz` answer 200;
      `SHOW password_encryption` answers `scram-sha-256`; `pg_hba_file_rules`
      holds no `trust` and no `md5` rule; `CREATE TABLE t (i int)` as
      `phyllon_runtime` fails with "permission denied"; `scripts/posture.sh`
      passes. It always runs `compose down -v` at the end.
- [x] **Step 7: Run it.** Run `scripts/stack-test.sh docker` with the image from
      Task 11. Expected: every check passes; the posture script prints its
      passed count.
- [x] **Step 8: Add the `stack-docker` job** to `ci.yml`: build the image from
      the pull request, run `scripts/stack-test.sh docker` with it. Add
      `stack-docker` to the required checks in `scripts/github-settings.sh` and
      apply after Mika confirms.
- [x] **Step 9: Ship.** Title:
      `feat(deploy): add the compose stack with Caddy and PostgreSQL`.

Done: merged in ccea2b3 (#20) on 2026-10-30; stack-docker required from then on.

### Task 13: Quadlet units and the Podman check (spike first)

**Files:**

- Create: `deploy/quadlet/` (`phyllon.container`, `phyllon-db.container`,
  `phyllon-proxy.container`, `phyllon-edge.network`, `phyllon-db.network`,
  `phyllon-db.volume`, `phyllon-caddy.volume`), `scripts/quadlet-test.sh`,
  `scripts/ci/fedora-vm.sh`, `.github/workflows/podman.yml`,
  `docs/decisions/0005-podman-ci.md`
- Modify (only if testing shows the need): `compose.yaml`, `compose.podman.yaml`

**Interfaces:**

- Consumes: `scripts/stack-test.sh`, `scripts/posture.sh`.
- Produces: `scripts/ci/fedora-vm.sh`, which boots a Fedora Cloud VM under KVM
  and runs a command inside it as an unprivileged user.

- [x] **Step 1: Spike the VM.** Write `fedora-vm.sh`: open `/dev/kvm` with the
      udev rule from the design, download the current Fedora Cloud Base qcow2
      and its `CHECKSUM` file, verify the checksum file's signature against
      Fedora's published key and the image against the checksum, boot it with a
      cloud-init seed holding a generated SSH key, and run a command over SSH. A
      first `podman.yml` runs only `getenforce` and `podman info` in the VM.
      Push it on the branch (main session, key dialog) and run it three times.
      Expected: `Enforcing`; note the duration of each run.
- [x] **Step 2: Decide the path.** At 15 minutes or less per run and three green
      runs, pull requests keep the VM job. Otherwise the fallback from the
      design: a nightly run on the maintainer's hardware that pulls `main`.
      Write `0005-podman-ci.md` with the numbers.
- [x] **Step 3: Run the stack under rootless Podman in the VM.** Run
      `scripts/stack-test.sh podman` there. Expected trouble: SELinux denies the
      bind-mounted secrets, config and init script. Fix with the `z` option on
      those mounts in `compose.yaml` if Docker still passes
      `scripts/stack-test.sh docker` with it; otherwise put the option in
      `compose.podman.yaml`. Expected afterwards: every check passes with
      SELinux enforcing.
- [x] **Step 4: Write the Quadlet units:** the networks (`Internal=true` on
      `phyllon-db`), the volumes, `Secret=` for the passwords, `Notify=healthy`,
      the config as a single-file bind mount with `:Z` from
      `~/.config/phyllon/phyllon.toml`, `Image=ghcr.io/nemesis398/phyllon:0.1`
      with `AutoUpdate=registry`, and the same posture settings as compose
      (`ReadOnly=`, `DropCapability=ALL`, `NoNewPrivileges=true`, `Memory=`,
      `PidsLimit=`). The proxy unit adds `AddCapability=CAP_NET_BIND_SERVICE`,
      for the same reason as compose: the caddy binary carries that file
      capability and does not start without it (Mika, 2026-10-30).
- [x] **Step 5: Write `scripts/quadlet-test.sh`,** which installs the units for
      the VM user, creates the Podman secrets, runs
      `systemctl --user daemon-reload` and starts them, waits for
      `phyllon.service` to report healthy, repeats the checks of
      `stack-test.sh`, and removes everything.
- [x] **Step 6: Finish `podman.yml`:** on pull requests touching
      `compose*.yaml`, `deploy/**` or `Dockerfile`, and nightly; it builds the
      image, copies it into the VM, and runs `stack-test.sh podman` and
      `quadlet-test.sh`. Expected: green.
- [x] **Step 7: Ship.** Title:
      `feat(deploy): add Quadlet units and prove the stack under SELinux`.

Done: merged in 1f7f905 (#21) and c6b94fd (#22) on 2026-10-30.

### Task 14: The install guide

**Files:**

- Create: `docs/install.md`, `deploy/examples/compose.traefik.yaml`

**Interfaces:**

- Consumes: the commands `scripts/stack-test.sh` and `scripts/quadlet-test.sh`
  run, which the guide repeats for a person.

- [x] **Step 1: Write `docs/install.md`.** Sections: what you need; the
      quickstart on `localhost` (secrets, `.env`, `compose up -d --wait`,
      `https://localhost:8443`, why the browser warns about Caddy's local CA); a
      public installation (`PHYLLON_DOMAIN`, ports 80 and 443, and under
      rootless Podman the one root step `net.ipv4.ip_unprivileged_port_start=80`
      in `/etc/sysctl.d/`, said plainly as the only root step); Quadlet on
      Fedora; behind an existing proxy; upgrades (the `0.1` line takes patch
      releases, moving to `0.2` is a deliberate edit, migrations only ever
      arrive with a minor version); what phase 1 cannot do yet. Task 21 adds
      "Verifying a release".
- [x] **Step 2: Write `deploy/examples/compose.traefik.yaml`,** an override that
      removes nothing from `compose.yaml` but attaches `phyllon` to an external
      network `proxy` with the Traefik labels `traefik.enable=true`, a
      `Host(...)` router rule from `PHYLLON_DOMAIN`, the `websecure` entry
      point, a `certresolver` placeholder named as one, and
      `loadbalancer.server.port=8080`. The guide explains removing `proxy` from
      `COMPOSE_PROFILES`.
- [x] **Step 3: Check the override.** Run
      `docker compose -f compose.yaml -f deploy/examples/compose.traefik.yaml config`
      with a stub external network. Expected: valid output with the labels on
      `phyllon`.
- [x] **Step 4: Ship.** Title: `docs: add the install guide`.

Done: merged in 4dd489c (#23) on 2026-10-30.

## Part 6: The shell (PHY-18)

### Task 15: The web UI shell

**Files:**

- Create: `src/web/mod.rs`, `src/web/strings.rs`, `templates/base.html`,
  `templates/index.html`, `templates/error.html`, `assets/phyllon.css`,
  `assets/fonts/` (Atkinson Hyperlegible Next 400 and 700, Fraunces 600, as
  WOFF2, with `OFL-AtkinsonHyperlegibleNext.txt` and `OFL-Fraunces.txt`),
  `tests/web.rs`
- Modify: `src/http/mod.rs` (mount the web routes, use the branded 404 and 500),
  `src/config.rs` (nothing new: `source_url` exists), `Cargo.toml` (askama),
  `scripts/stack-test.sh` (check that `/` contains "Phyllon")

**Interfaces:**

- Consumes: `AppState`, `BuildInfo`, `AppError`, `with_security_layers`.
- Produces:

```rust
pub fn routes() -> axum::Router<AppState>                                  // "/" and "/assets/{*path}"
pub async fn not_found() -> axum::response::Response                       // the branded 404
pub fn error_page() -> axum::response::Response                            // the branded generic 500, also behind AppError
```

Assets are compiled in with `include_bytes!`; the palette is `brand/palette.css`
itself, served at `/assets/palette.css`, so the brand keeps one source. Logos
come from `brand/logo.svg`, `brand/logo-dark.svg` (in a `<picture>` with a
`prefers-color-scheme: dark` source) and `brand/favicon.svg`. Assets answer with
`Cache-Control: public, max-age=3600`. Templates render to a `String` and return
`Html`; no askama integration crate.

- [x] **Step 1: Fetch the fonts.** From `github.com/google/fonts` at a pinned
      commit, `ofl/atkinsonhyperlegiblenext` and `ofl/fraunces`. Subset to
      Latin, Latin-1, Latin Extended-A, general punctuation and the math
      operators block, as WOFF2, with `pyftsubset`; each file under 100 KB.
      Record the commit and the command in the pull request.
- [x] **Step 2: Write the failing tests** in `tests/web.rs`:
      `start_page_names_phyllon_and_links_the_source` (200, `text/html`,
      contains "Phyllon", the version, and
      `href="https://github.com/nemesis398/phyllon/tree/abc123"` for a build
      with commit `abc123`); `the_shell_carries_the_security_headers` (the five
      headers on `/` and on `/assets/phyllon.css`);
      `assets_have_their_types_and_cache_headers` (`/assets/phyllon.css` is
      `text/css`, `/assets/fonts/atkinson-hyperlegible-next-400.woff2` is
      `font/woff2`, `/assets/logo.svg` is `image/svg+xml`, an unknown asset is
      404); `pages_load_nothing_from_other_origins` (no `src=` or `<link href=`
      with `http://` or `https://` in `/` or the 404 page, and no `<script` at
      all); `the_not_found_page_is_branded` (404, contains "Page not found" and
      a link to `/`); `a_panic_shows_the_branded_error_page` (500, contains the
      error page's heading, not the panic message).
- [x] **Step 3: Run them.** Expected: compile errors.
- [x] **Step 4: Implement** `web/`, the templates and `phyllon.css`. The layout
      is a header with the mark and the wordmark "Phyllon" set in Fraunces 600,
      a main area that says what Phyllon is and that there is nothing to sign in
      to yet, and a footer with the version, "AGPL-3.0-or-later" and the source
      link. All English strings live in `strings.rs`.
- [x] **Step 5: Run the tests and the gate.** Expected: seven passes;
      `scripts/check.sh` passes.
- [x] **Step 6: Ship.** Title:
      `feat(web): add the shell in the brand, light and dark`.

Done: merged in 3dbb579 (#24) on 2026-10-30.

### Task 16: The browser checks

**Files:**

- Create: `tests/browser/shell.spec.ts`, `playwright.config.ts`
- Modify: `package.json` and `package-lock.json` (`@playwright/test`,
  `@axe-core/playwright`), `.github/workflows/ci.yml` (a `browser` job)

**Interfaces:**

- Consumes: a running `phyllon serve` on `PHYLLON_BASE_URL`.

- [ ] **Step 1: Write the tests.** For each color scheme, `light` and `dark`,
      with `page.emulateMedia({ colorScheme })`:
      `start page has no accessibility violations` (axe `violations` is empty
      for `/`); `not found page has no accessibility violations` (same for
      `/no-such-page`); `no request leaves the origin` (every request URL
      recorded while loading `/` has the base URL's origin); a full-page
      screenshot to `test-results/shell-<scheme>.png`.
- [ ] **Step 2: Run them locally** against `cargo run -- serve` with a config
      whose database is `127.0.0.1:1`. Expected: all pass. A failure here is a
      finding against the shell, fixed in the shell, never by loosening the
      check.
- [ ] **Step 3: Add the `browser` job:** build, start the binary, wait for
      `/healthz`, `npx playwright install --with-deps chromium`, run the tests,
      upload `test-results/` as an artifact. Add `browser` to the required
      checks in `scripts/github-settings.sh` and apply after Mika confirms.
- [ ] **Step 4: Ship.** Title:
      `test(web): check the shell for accessibility in light and dark`.

## Part 7: Skills and the map (PHY-14)

### Task 17: The five skills

**Files:**

- Create:
  `.agents/skills/{conscience,before-you-build,review,docs-style,commits}/SKILL.md`,
  `.agents/skills/conscience/reference/{principles,patterns,lineage-and-sources}.md`,
  the symlinks `.claude/skills/<name>` to `../../.agents/skills/<name>`,
  `scripts/ci/check-skill-links.sh`
- Modify: `scripts/ci/test.sh` (cases for the link check), `AGENTS.md` (the
  Codex answer), `CONTRIBUTING.md` (the skill-copy answer)

**Interfaces:**

- Produces: `scripts/ci/check-skill-links.sh`, which exits 1 when a link in
  `.claude/skills/` does not resolve to a `SKILL.md` in `.agents/skills/`, or a
  skill there has no link.

- [ ] **Step 1: Write the failing link-check cases:** a resolving link passes; a
      dangling link fails and names it; a skill directory without a link fails
      and names it. Run `scripts/ci/test.sh`; they fail.
- [ ] **Step 2: Write `check-skill-links.sh`;** the cases pass.
- [ ] **Step 3: Publish the conscience.** Copy
      `~/.claude/skills/muratori-conscience/` (Mika's own skill) to
      `.agents/skills/conscience/`. Rename it to `conscience` in the frontmatter
      and the title, drop the person's name from the name and the description,
      keep every credit in `reference/lineage-and-sources.md`, add a line naming
      Mika Böhme with an AI as the authors under the repository's license, and
      replace every em dash (236 today) so the house style holds.
- [ ] **Step 4: Write `commits`** from the shape of Mika's conventional-commits
      skill, monolingual English: the types, the scopes this repository uses,
      the claims checked against the diff, the sign-off rule, the
      `Co-Authored-By:` trailer, and the pull request title as the commit on
      `main`.
- [ ] **Step 5: Write `docs-style`:** no em dashes, American spelling,
      sentence-case headings, emoji only as heading labels, Markdown through
      prettier and markdownlint with the repository's configs.
- [ ] **Step 6: Write `before-you-build`:** the decision tree from the design
      (its Mermaid diagram), and per candidate the checks with their commands:
      the license through `cargo deny`, maintenance (a release in the last 12
      months), advisories, proof that the crate exists (`cargo info`), the 7-day
      wait, the pinned version's docs on docs.rs, and a decision record.
- [ ] **Step 7: Write `review`:** a review in a fresh session, ideally another
      model family, given the diff and the spec but not the author's reasoning;
      the security checklist from rule 12 of the engineering research; every
      finding becomes a failing test before any fix.
- [ ] **Step 8: Answer the two open points.** Whether a project-level Claude
      Code setting can hide a contributor's personal copy of a skill the
      repository ships: check the settings docs and the binary, and write the
      answer in CONTRIBUTING. Whether Codex CLI runs hooks: check its docs, and
      write in AGENTS.md either how Codex runs the gate or that the git hook and
      CI are its only gate.
- [ ] **Step 9: Check everything.** Run `scripts/ci/check-skill-links.sh`, the
      Markdown checks and the prose rule (no `—` anywhere: `rg -c '—' .agents`
      prints nothing). Expected: all pass. Add the link check to the `scripts`
      job.
- [ ] **Step 10: Ship.** Title:
      `docs: add the five skills, the conscience included`.

### Task 18: The map and the first decision records

**Files:**

- Create: `docs/map.md`, `scripts/ci/check-map.sh`,
  `docs/decisions/0002-one-package.md`,
  `docs/decisions/0003-axum-and-askama.md`, `docs/decisions/0004-caddy.md`
- Modify: `scripts/ci/test.sh`, `.github/workflows/ci.yml`

**Interfaces:**

- Produces: `scripts/ci/check-map.sh`, which compares the modules of `src/`
  (each `src/*.rs` other than `lib.rs` and `main.rs`, and each directory
  `src/*/`) with the headings `` ## `name` `` in `docs/map.md`, and exits 1
  naming each module the map lacks and each heading without a module.

- [ ] **Step 1: Write the failing cases:** a matching map passes; a module
      without a heading fails and names it; a heading without a module fails and
      names it. Run them; they fail.
- [ ] **Step 2: Write `check-map.sh`;** the cases pass.
- [ ] **Step 3: Write `docs/map.md`** for `cli`, `config`, `db`, `http` and
      `web`: what each owns, its invariants (for example: every response passes
      `with_security_layers`; no secret reaches a log or a `Debug` string; the
      web routes and the MCP routes of phase 2 never share a router), and its
      decision records.
- [ ] **Step 4: Write records 0002 to 0004** in the format of 0001. 0004 carries
      the comparison with Traefik from 2026-10-29: Caddy 2.11.7 against Traefik
      3.7.16, the images at 24.9 MB against 55.4 MB, the container socket that
      label discovery needs, and the advisory counts with the note that most of
      them hit features Phyllon does not use.
- [ ] **Step 5: Run the map check** on the real tree and add it to the `scripts`
      job. Expected: exit 0.
- [ ] **Step 6: Ship.** Title:
      `docs: add the module map and the first decision records`.

## Part 8: Releases (PHY-17)

### Task 19: The release spike

**Files:**

- Create: `docs/decisions/0006-release-pipeline.md`

- [ ] **Step 1: Set up a throwaway repository.** After Mika agrees in the
      question dialog, create the public repository
      `nemesis398/phyllon-release-spike` with a minimal crate,
      `release-plz.toml` (`git_only = true`, `git_release_draft = true`,
      `git_release_type = "pre"`, `release_always = false`) and immutable
      releases on.
- [ ] **Step 2: Try dist.** Run `dist init` with GitHub attestations, and make
      its generated workflow attach to the draft that release-plz created, then
      publish only after verification. Its build and attest steps have to run
      inside a reusable workflow (`on: workflow_call`) that the release workflow
      calls, for SLSA Build Level 3. Note every edit the generated workflow
      needed.
- [ ] **Step 3: Try our own build job:** a reusable workflow in which two native
      runners build the static binaries and attest them; the calling workflow
      uploads them to the draft, verifies them with `--signer-workflow` and
      publishes. Its build job runs with `step-security/harden-runner` in block
      mode (Mika, 2026-10-30), so the spike learns the allowlist: the audit
      output of a first run gives the hosts, and Task 20 takes the list from
      here.
- [ ] **Step 4: Release a branch named `release-plz-v0.1.0` from each variant,**
      and check that `release_always = false` releases a merge from that branch
      and ignores an ordinary merge.
- [ ] **Step 5: Decide and record.** dist stays if it fits the
      draft-then-publish order and builds inside the reusable workflow with its
      generated workflow intact; otherwise the own job. Check with
      `gh attestation verify --signer-workflow` that each variant's attestation
      names the reusable workflow as its signer, not the caller. Write 0006 with
      what each needed. Then, after Mika agrees, delete the spike repository.

### Task 20: The release workflow

**Files:**

- Create: `release-plz.toml`, `scripts/prepare-release.sh`,
  `.github/workflows/release.yml`, `.github/workflows/build.yml`,
  `deploy/compose.release.yaml.tmpl`
- Modify: `scripts/github-settings.sh` (if the release needs a setting)

**Interfaces:**

- Consumes: the decision in 0006.
- Produces: `scripts/prepare-release.sh [VERSION]`, which checks that `main` is
  clean and current, cuts `release-plz-v<version>`, runs
  `release-plz set-version phyllon@VERSION` when a version is given and
  `release-plz update` otherwise, commits `chore(release): v<version>` with the
  sign-off, and stops before the push, which the main session does after the key
  dialog.

- [ ] **Step 1: Write `release-plz.toml`** with the four settings from Task 19
      and `publish = false`.
- [ ] **Step 2: Write `prepare-release.sh`** and run it with `--dry-run` on a
      scratch clone. Expected: the branch, the version in `Cargo.toml` and the
      changelog entry, no push.
- [ ] **Step 3: Write `build.yml`** (`on: workflow_call`, with the version as
      input and the binaries' names and the image digest as outputs), as 0006
      decided. It does everything that produces or signs an artifact: binaries
      for `x86_64-unknown-linux-musl` and `aarch64-unknown-linux-musl` on native
      runners, built with `cargo auditable build --release --locked` (Mika,
      2026-10-30), with a CycloneDX SBOM each from `cargo-cyclonedx`; the image,
      built per architecture by digest and merged into one manifest tagged with
      the version and its minor line, with `sbom: true` and
      `provenance: mode=max`; `actions/attest` for every binary, SBOM and the
      image digest; `cosign sign --yes` on the image digest. Each job holds only
      the permissions its step needs (`attestations: write`, `id-token: write`,
      `contents: read`, and `packages: write` for the image). The first step of
      every job is the pinned `step-security/harden-runner` with
      `egress-policy: block` and the `allowed-endpoints` that Task 19 learned:
      crates.io, static.crates.io, index.crates.io, static.rust-lang.org,
      github.com, api.github.com, ghcr.io and its blob hosts, Sigstore's fulcio,
      rekor and tuf hosts, and the base image registries (Mika, 2026-10-30).
- [ ] **Step 4: Write `release.yml`,** with a `concurrency` group and per-job
      permissions, and the same Harden-Runner first step in every job that has
      steps, each job with only the endpoints it needs. Jobs: `release-plz` (tag
      and draft; outputs whether a release was created and its tag); `build`,
      which calls `build.yml` only when a release was created; the release's
      `compose.yaml`, rendered from the template with the image digest;
      `verify`, which runs
      `gh attestation verify --signer-workflow nemesis398/phyllon/.github/workflows/build.yml`
      on every file and on `oci://ghcr.io/nemesis398/phyllon:<version>`, and
      `cosign verify` with
      `--certificate-identity https://github.com/nemesis398/phyllon/.github/workflows/build.yml@refs/heads/main`
      and
      `--certificate-oidc-issuer https://token.actions.githubusercontent.com`;
      `publish`, which runs only when `verify` passed and turns the draft into a
      published pre-release.
- [ ] **Step 5: Lint them.** Run `actionlint` and `zizmor` on both workflows.
      Expected: no findings.
- [ ] **Step 6: Ship.** Title:
      `ci: build, attest, sign and verify releases before publishing`. A merge
      of this pull request releases nothing, because `Cargo.toml` still says
      `0.0.0` and the branch is not a release branch.

### Task 21: The first release, `v0.1.0`

**Files:**

- Modify: `Cargo.toml`, `CHANGELOG.md` (through the script), `docs/install.md`
  ("Verifying a release"), `.github/workflows/nightly.yml`, `README.md`,
  `docs/decisions/0007-podman-signature-policy.md` (only if Step 5 fails)

- [ ] **Step 1: Prepare it.** Run `scripts/prepare-release.sh 0.1.0`, push after
      the key dialog, open the pull request. Expected: CI green.
- [ ] **Step 2: Merge it after Mika's yes.** Expected: `release.yml` runs to
      `publish`; the release `v0.1.0` exists as a pre-release with both
      binaries, their SBOMs and `compose.yaml`.
- [ ] **Step 3: Mika makes the GHCR package public** in its package settings,
      since a new package starts private and the API cannot change that.
- [ ] **Step 4: Verify from outside.** On a machine that did not build it, run
      these two and the `cosign verify` command from Task 20. Expected: all
      three succeed, and the attestation's predicate names `build.yml` as the
      build workflow.

  ```bash
  signer=nemesis398/phyllon/.github/workflows/build.yml
  gh attestation verify phyllon-x86_64-unknown-linux-musl \
    -R nemesis398/phyllon --signer-workflow "$signer"
  gh attestation verify oci://ghcr.io/nemesis398/phyllon:0.1.0 \
    -R nemesis398/phyllon --signer-workflow "$signer"
  ```

- [ ] **Step 5: Spike the Podman signature policy.** Write a `policy.json` that
      requires a `sigstoreSigned` keyless signature from the build workflow's
      identity for `ghcr.io/nemesis398/phyllon`, and pull `0.1` with it under
      rootless Podman. Expected: the pull succeeds, and a pull of an unsigned
      image under the same name prefix is refused. If Podman cannot match a
      workflow identity, write 0007 with the fallback (verify with cosign before
      an update, and no `AutoUpdate=` in the Quadlet unit).
- [ ] **Step 6: Write "Verifying a release"** in the install guide with the
      commands from Steps 4 and 5.
- [ ] **Step 7: Scan the published image every night** (Mika, 2026-10-30). This
      needs the public package from Step 3, since a scan cannot pull a private
      image. Add a job to `nightly.yml` with `contents: read` and
      `security-events: write`: a pinned `anchore/scan-action` (Grype) on
      `ghcr.io/nemesis398/phyllon:0.1` with `fail-build: true`,
      `severity-cutoff: high` and SARIF output, then a pinned
      `github/codeql-action/upload-sarif`. Grype reads the crate list that
      `cargo auditable` embedded. Add `workflow_dispatch` if the file lacks it,
      and move the tag when the minor line moves. Expected: a manual run from
      the pull request's branch is green, the log lists the binary's Rust
      crates, and the SARIF shows in code scanning.
- [ ] **Step 8: Add the release badge to the README** (Mika, 2026-10-30), now
      that a release exists: the image
      `https://img.shields.io/github/v/release/nemesis398/phyllon?include_prereleases&sort=semver`,
      linking to `https://github.com/nemesis398/phyllon/releases`. Expected: the
      badge shows `v0.1.0`.
- [ ] **Step 9: Ship** the guide, `nightly.yml` and the README badge in one pull
      request. Title:
      `ci: scan the published image and explain how to verify a release`.

## Part 9: Acceptance

### Task 22: Show each line of "When phase 1 is done"

- [ ] **Step 1: The repository files.**
      `gh api repos/nemesis398/phyllon/community/profile --jq .health_percentage`
      prints `100`; a fresh clone at `v0.1.0` that follows `docs/install.md`
      reaches a running stack on `localhost`.
- [ ] **Step 2: The stack.** The latest `stack-docker` run and the latest Podman
      run are green, each ending with the posture script's output.
- [ ] **Step 3: The gate bites.** A throwaway pull request that adds an
      `unwrap()` turns `gate` red; close it unmerged. `.githooks/pre-commit` and
      the Stop hook refuse the same change locally.
- [ ] **Step 4: The map and skill checks bite.** One throwaway pull request with
      a module missing from the map and one with a dangling skill link both turn
      `scripts` red; close both unmerged.
- [ ] **Step 5: The release.** Link the `v0.1.0` release, its `verify` job
      (which shows the `--signer-workflow` check, the SLSA Build Level 3
      evidence) and records 0006 and, if written, 0007.
- [ ] **Step 6: The shell.** Link the `browser` run and its two screenshots.
- [x] **Step 7: The best practices badge** (Mika, 2026-10-30). Stop and ask in
      the question dialog: only Mika can do this. Mika registers the project at
      <https://www.bestpractices.dev> and fills in the passing-level form. Then
      add the badge, `https://www.bestpractices.dev/projects/<id>/badge` with
      the ID from the registration, to the README, linking to the project page.
      Scorecard reads the registration; the badge only shows it. Title:
      `docs: show the best practices badge in the README`.
- [ ] **Step 8: Loose ends.** `scripts/github-settings.sh audit` exits 0; the
      latest Scorecard run shows Pinned-Dependencies, Token-Permissions and
      Dangerous-Workflow at 10 and CII-Best-Practices above 0;
      `curl -sI https://phyllon.de` redirects to the repository. GitHub's
      workflow lockfiles have their month of use on 2026-11-28: if phase 1
      closes earlier, add a Plane item to look at them then.
- [ ] **Step 9: Close M1.** Mark PHY-9 to PHY-18 done with their evidence, close
      M1 on Plane and the milestone `M1 Foundations` on GitHub, update the
      project paper's milestone line through `/project update`, and set M2's
      date.
