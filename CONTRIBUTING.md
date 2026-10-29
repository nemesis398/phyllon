# Contributing to Phyllon

Thank you for helping. This file says what a pull request needs. By taking part
you agree to the [code of conduct](CODE_OF_CONDUCT.md).

The hooks, the gate script and CI described below arrive later in phase 1.

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
- About 400 changed lines at most, not counting lockfiles, generated files and
  vendored text such as license texts.
- Every pull request is squash merged, so the title becomes the commit on
  `main`. Make it a [conventional commit](https://www.conventionalcommits.org/)
  of at most 72 characters, for example `feat: add the health endpoint`.
- Fill in the pull request template. It asks for the sign-off, what ran, what
  did not, and what you are unsure of.

## Turn on the hooks

Run this once in your clone:

```sh
git config core.hooksPath .githooks
```

The pre-commit hook then runs the gate before each commit that touches Rust or
Cargo files.

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
