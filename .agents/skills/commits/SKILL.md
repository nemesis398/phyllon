---
name: commits
description: >-
  Writes and reviews commit messages and pull request titles for this
  repository: Conventional Commits with the types and scopes its history uses,
  every claim checked against the diff, the sign-off added only on the directing
  person's instruction together with the agent's Co-Authored-By trailer, and the
  pull request title as the squash commit on main. Load it before every commit,
  before opening or renaming a pull request, and when asked to review or clean
  up a commit message.
---

# Commits

Every pull request is squash merged. Its title becomes the subject of the one
commit on `main`, and the branch's commits end up as a list in that commit's
body. release-plz reads the types on `main` to raise the version and write the
changelog, so a wrong type ships a wrong version.

## Read the diff first

Never describe a change you have not read.

```sh
git status
git diff --cached       # what this commit holds
git diff main...HEAD    # what the pull request holds
```

Check every claim in the message against that output before you keep it. "Bump a
crate" needs a staged `Cargo.toml` and `Cargo.lock`
(`git diff --cached --name-only`). "Breaking" needs a line the diff adds, not
one that was already there (`git log -S'<text>' --oneline` shows when it came
in). Say what the diff does not contain rather than carry a claim over.

Stage by path (`git add <paths>`), not with `git add -A`, so nothing unrelated
comes along. A diff that does two things of different types is two commits.

## The subject

```text
<type>(<scope>)!: <summary>
```

- **Type**, one of the eleven that `scripts/ci/check-pr-title.sh` accepts:
  `feat` (new behavior), `fix` (a bug fix), `docs`, `style` (formatting only),
  `refactor` (no change in behavior), `perf`, `test`, `build` (Cargo, npm, the
  Dockerfile, the toolchain), `ci` (workflows and CI scripts), `chore` and
  `revert`.
- **Scope**, optional: lowercase letters, digits and dashes. Use one this
  repository already uses, which `git log --format=%s -40` lists: `web`, `http`,
  `config`, `cli`, `deploy` and `plan`, and `deps` as Dependabot writes it
  (`build(deps)` for crates, npm packages, images and the toolchain, `ci(deps)`
  for actions). A new module gets its module's name. Leave the scope out when
  the change spans areas.
- **`!`** before the colon marks a breaking change, together with a
  `BREAKING CHANGE: <what breaks>` footer in the body.
- **Summary**: imperative, lowercase after the colon, no trailing period, the
  whole line at most 72 characters. Name the effect, not the mechanism:
  `feat(http): serve health and readiness with the security headers`.

## The body

Leave a blank line, wrap at 72 characters, and say why the change is the way it
is and what the diff does not show. It is plain text for people, so the
`docs-style` skill applies: no em dashes, American spelling.

## Sign-off and credit

Rule 16 of [AGENTS.md](../../../AGENTS.md) and
[CONTRIBUTING.md](../../../CONTRIBUTING.md) decide this:

- Add a sign-off only when the person who directs you has told you to commit.
  Then commit with `git commit -s`, which appends a `Signed-off-by:` line from
  `user.name` and `user.email`; check with `git config user.email` that they are
  that person's.
- End the message with your own `Co-Authored-By:` trailer, which names you, for
  example `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Without that instruction, do not commit: CI rejects a commit without a
  sign-off. Leave the change in the working tree and say what is ready.
- Never sign off for anyone but that person, and never for yourself. The
  sign-off certifies the
  [Developer Certificate of Origin](https://developercertificate.org/), which
  only a human can do, and that person reviews the pull request before it
  merges.

```text
docs: add the commits skill

Say why in a sentence or two.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Signed-off-by: Jane Doe <jane@example.com>
```

The sign-off must equal the commit's author name and email. Check the branch as
CI does, and repair a commit that fails with `git commit --amend -s` or
`git rebase --signoff main`:

```sh
scripts/ci/check-signoff.sh main HEAD
```

The pre-commit hook in `.githooks/` runs `scripts/check.sh` when the commit
touches Rust or gate files. Never skip it with `--no-verify`; fix what fails.

## The pull request title

The title is the commit on `main`, so it follows the subject rules above and
sums up the whole pull request, not its last commit. CI's `pr-title` job runs
the check; run it yourself first:

```sh
scripts/ci/check-pr-title.sh 'feat(web): add the shell in the brand'
```

It passes one line of the form `type(scope)!: summary` with a type from the
list, an optional scope of lowercase letters, digits and dashes, an optional
`!`, a colon, one space and a summary that starts with a non-space character, at
most 72 characters counted as characters, not bytes. GitHub appends the pull
request number, as in `(#26)`, when it merges.

## Reviewing a message

Check in this order, and name the rule each problem breaks:

1. Every claim matches the diff.
2. One change, or it needs splitting.
3. Type, scope and summary as above; `!` and `BREAKING CHANGE:` where it breaks.
4. Body after a blank line, wrapped at 72; trailers last, in the order shown.
