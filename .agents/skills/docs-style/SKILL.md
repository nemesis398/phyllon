---
name: docs-style
description: >-
  The house style for prose in this repository: no em dashes, American spelling,
  sentence-case headings, emoji only as heading labels, and Markdown formatted
  by prettier and checked by markdownlint-cli2 with the repository's configs.
  Load it before writing or editing any Markdown file, a doc comment, a code
  comment meant for people, a commit message body or a pull request description.
---

# Docs style

Docs, comments, commit bodies and pull request descriptions follow these rules.
CI's `markdown` job enforces the formatting; the rest is on you.

## No em dashes

The em dash (U+2014) appears nowhere: not in headings, tables, comments,
diagrams or commit messages. Restructure the sentence instead, with a comma, a
colon, parentheses or two sentences.

```text
good  The hook runs the gate, but only for Rust files.
good  The hook runs the gate. It skips commits without Rust files.
```

This prints nothing when the files you touched are clean:

```sh
rg -n '\x{2014}' <files>
```

## American spelling

`behavior`, `color`, `center`, `organize`, `catalog`, `canceled`, and `license`
for the noun and the verb alike.

## Headings

- One `#` title per file. Every heading below it is in sentence case:
  `## Turn on the hooks`, not `## Turn On The Hooks`.
- Proper nouns and code keep their own case: `GitHub`, `PostgreSQL`,
  `cargo-deny`, `` `scripts/check.sh` ``.
- Sibling headings have different names (markdownlint's MD024).

## Emoji

An emoji is a label, not decoration. It may open a heading a reader scans for,
one per heading, matched literally to the content, as in `## 🔏 Releases`. Never
use the same one twice in a document, and never one in body text, lists, tables
or code comments. Most headings need none.

## Writing

- Say the thing instead of announcing it: cut "it's worth noting" and note it.
- Be concrete: numbers, names, versions and dates, not "significant".
- Name who does it. "The workflow signs the image" beats "the image is signed".
- Delete a closing sentence that restates the paragraph.
- Bold marks a landmark, at most about once per paragraph.

## Markdown

- Link repository files with relative links, and wrap a bare URL in angle
  brackets: `<https://docs.rs/>`.
- A Mermaid diagram copies its `%%{init: ...}%%` line from an existing one, such
  as the release diagram in [CONTRIBUTING.md](../../../CONTRIBUTING.md), so
  every diagram carries the brand.

Format with prettier first, then lint with markdownlint-cli2:

```sh
npm ci --ignore-scripts
npx prettier --write <files>
npx markdownlint-cli2 --fix <files>
npx prettier --check .
npx markdownlint-cli2
```

The configs are in the repository root. `.prettierrc.yaml` wraps prose at 80
columns. `.markdownlint-cli2.yaml` limits lines to 80 characters, exempts tables
and code blocks, and skips `.superpowers/`, `CODE_OF_CONDUCT.md` and
`CLAUDE.md`. Both configs and `.prettierignore` are gate files (rule 3 of
[AGENTS.md](../../../AGENTS.md)): fix the text, not the config.
