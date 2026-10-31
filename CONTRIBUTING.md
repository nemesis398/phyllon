# Contributing to Phyllon

Thank you for helping. This file says what a pull request needs. By taking part
you agree to the [code of conduct](CODE_OF_CONDUCT.md).

## Sign-off

Phyllon uses the
[Developer Certificate of Origin](https://developercertificate.org/). By signing
off a commit you certify that you wrote the change or have the right to submit
it under the project's license, AGPL-3.0-or-later, and that you do so in public.

Add the sign-off with `git commit -s`. It appends one line to the message:

```text
Signed-off-by: Your Name <you@example.com>
```

It must match the commit's author name and email. CI checks every commit of a
pull request for it.

An agent may add the sign-off of the person who directs it, only on that
person's instruction, and the agent is credited with a `Co-Authored-By:`
trailer. That person reviews the pull request before it merges.

## Pull requests

- One concern per pull request.
- New or changed behavior comes with tests. Write each test first and watch it
  fail. A bug fix comes with a test that reproduces the bug. Cover the edge
  cases listed in rule 11 of [AGENTS.md](AGENTS.md).
- About 400 changed lines at most, not counting lockfiles, generated files and
  vendored text such as license texts.
- Every pull request is squash merged, so the title becomes the commit on
  `main`. Make it a [conventional commit](https://www.conventionalcommits.org/)
  of at most 72 characters, for example `feat: add the health endpoint`.
- Fill in the pull request template. It asks for the sign-off, the tests, what
  ran, what did not, and what you are unsure of.

## Turn on the hooks

Run this once in your clone:

```sh
git config core.hooksPath .githooks
```

The pre-commit hook then runs the gate before each commit that touches Rust
code, another compile input such as a template, or Cargo files. It checks your
working tree, not what you staged, so unstaged changes and untracked files
count; CI checks exactly what was committed.

## The gate

`scripts/check.sh` runs the formatter, the linter, the tests and the dependency
checks. CI runs the same script as the first job of every pull request. Run it
before you push:

```sh
scripts/check.sh
```

Markdown goes through prettier and then markdownlint-cli2 with the configs in
the repository root:

```sh
npm ci
npx prettier --write .
npx markdownlint-cli2 --fix
```

## AI-assisted contributions

They are welcome, under the same rules as any other. You answer for every line
you submit, whoever or whatever wrote it. The pull request says what ran, what
did not, and what you are unsure of.

## Skills for agents

The repository ships its agent skills in `.agents/skills/`, which Codex reads
directly. Claude Code reads them through the links in `.claude/skills/`, and CI
runs `scripts/ci/check-skill-links.sh` to check that every skill has its link.

If you keep a personal Claude Code skill in `~/.claude/skills/` with the name of
a shipped one, such as `review`, yours runs and the shipped one does not: Claude
Code ranks a personal skill above a project skill of the same name. No setting
in the repository can change that. `skillOverrides` matches skills by name only,
so an entry there would hide the name, not your copy alone, and
`strictPluginOnlyCustomization`, which can block personal skills, works only in
managed settings and blocks project skills as well. So rename your copy, both
its directory and its `name` field, or remove it while you work here. Codex
keeps both: two skills of one name can both appear in its skill selector.

Sources, checked on 2026-10-30 with Claude Code 2.1.314: the
[skills page](https://code.claude.com/docs/en/skills.md), sections "Resolve
skills that share a name" and "Override skill visibility from settings"; the
[settings reference](https://code.claude.com/docs/en/settings-reference.md)
entries for `skillOverrides` and `strictPluginOnlyCustomization`; and
[Codex's skills page](https://developers.openai.com/codex/skills).
