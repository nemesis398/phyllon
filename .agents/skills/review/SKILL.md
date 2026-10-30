---
name: review
description: >-
  Gets a change reviewed in a fresh session, ideally by another model family,
  from the diff and the spec but not the author's reasoning, against the
  security checklist of the engineering research, and turns every finding into a
  failing test before any fix. Load it when a pull request is ready for review,
  when asked to review someone else's diff, and before acting on review
  findings.
---

# Review

A model reads its own output as its own and misses its errors there, but finds
them in code it reads as someone else's. Same-model self-review in one context
added 0 to 12.9 points in the studies, and a weaker model reviewing a stronger
one made results worse. So the review runs in a fresh context, ideally on
another model family and never a weaker one, and nothing it says counts until a
test or a tool confirms it. Sources: sections 2.3 and 8 (rule 12) of
[the engineering research](../../../docs/research/engineering-quality.md).

## Prepare the packet (author)

Collect the diff, and run cargo-mutants on it before anyone else reads it: kill
each surviving mutant with a stronger test, never by deleting code (rule 11 of
[AGENTS.md](../../../AGENTS.md)).

```sh
git diff main...HEAD > "${TMPDIR:-/tmp}/review.diff"   # since the merge base
git diff --stat main...HEAD
git log --format='%h %s' main..HEAD
cargo mutants --in-diff "${TMPDIR:-/tmp}/review.diff"
```

Give the reviewer the diff, the spec (the design section or plan task in
`docs/`, or the spec in the pull request), `AGENTS.md` and the checklist below.
Do not give it your reasoning: no chat transcript, no notes, no summary of why
the change is right. Start it as a new session with an empty context (another
tool such as Codex or Gemini CLI if you can), not as a follow-up in your own.

A prompt to start from:

```text
You did not write this change. Review the diff against the spec. For each
finding give the file and line, the input or sequence that triggers it, and a
test that would fail because of it. Go through every item of the security
checklist and write "checked, nothing found" for the ones that hold. Do not
fix anything.
```

## Security checklist

Rule 12 of the engineering research names these items. Check each one on every
changed path:

1. **Authorization on every endpoint and tool.** Each HTTP route and MCP tool
   checks who may call it, including the ones a diff only touches.
2. **Injection.** SQL only through `sqlx::query!` with bound parameters, never
   `format!` (rule 5); HTML through askama's escaping; no shell command built
   from input.
3. **SSRF.** A URL fetched on a user's behalf cannot reach internal addresses or
   the metadata service.
4. **Path traversal.** A path from input cannot leave its base directory through
   `..`, an absolute path or a symlink.
5. **Secrets in logs.** No key, password, token or full request body reaches a
   log, an error message or a test fixture (rule 14).
6. **Prompt injection into MCP tools.** Model output and fetched content are
   input like any other: they cannot widen a tool's rights or choose its target.
7. **Unbounded input.** Every body, upload, list and parser has a size limit,
   and a new parser has a property test or fuzz target (rule 6).

Then the rules a diff breaks most often: no `unsafe`, `unwrap`, `expect`,
`panic!`, `todo!` or unchecked indexing outside tests (rule 4); no gate file
touched without the maintainer's approval (rule 3); every new dependency
justified (rule 7); the edge cases of rule 11 covered; about 400 lines at most
(rule 9).

## Act on findings (author)

1. **Reproduce first.** Turn each finding into a test, run it and watch it fail
   (`cargo nextest run <test name>`). A finding that no test or tool can confirm
   is not a bug yet; say so in the pull request instead of changing code for it.
2. **Then fix,** watch the test pass, and run `scripts/check.sh`.
3. **Record it.** List each finding in the pull request description: what the
   reviewer said, the test that now covers it, or why you rejected it (rule 15).
   A bug that had already reached `main` also gets an entry in
   `docs/lessons.md`: the bug, the rule or test that now catches it, and the
   pull request.

## Review someone else's change (reviewer)

Read the spec before the diff, so you judge what the change should do and not
only what it does. Report findings in the prompt's shape and fix nothing; the
author turns them into tests.
