# Lessons

This file records each bug that an agent shipped and the rule or test that now
catches it. A lesson is useful only when something enforces it, so every entry
names the rule or the test, not just the moral.

Add an entry in the pull request that fixes the bug. Newest entries go first.

## Format

Each entry has a title and three fields:

```markdown
### Short name of the bug

- **Bug:** What went wrong, and how it was found.
- **Caught by:** The rule in `AGENTS.md`, or the test, that now catches it.
- **Pull request:** A link to the pull request that fixed it.
```

## Entries

### The install guide fell behind the shell

- **Bug:** From #24 on, `/` serves the start page with the brand, but
  `docs/install.md` still said that `/` answers 404, and v0.1.0 shipped with
  that guide. Task 14 of the phase 1 plan wrote the guide before Task 15 built
  the shell, and Task 15's file list left out `docs/install.md`, so nobody
  reopened it. Task 22's evidence run and the final review of phase 1 found it.
- **Caught by:** nothing automatic yet. `scripts/stack-checks.sh` asserts that
  `/` is the start page, but no check compares the guide with what the server
  answers. When a change alters what a route answers, its plan task must list
  `docs/install.md`, and the review must read the guide.
- **Pull request:** the one titled
  `docs: say what v0.1.0 serves and record the phase 1 lessons`.

### Config parse errors quoted the config file

- **Bug:** #14 printed toml's parse error as it was. Its `Display` quotes the
  offending line, its `Debug` holds the whole file, and serde's messages quote
  the rejected value, so a password pasted into `phyllon.toml` reached stderr,
  which is the log in a container. The review of #28 found it.
- **Caught by:** `no_parse_error_carries_text_of_the_file` in `tests/config.rs`,
  which puts a marker that only the file holds into each kind of error and fails
  if the marker shows in `Display` or `Debug`, and
  `healthcheck_names_a_bad_config_key_without_echoing_its_value` in
  `tests/cli.rs`, which checks the same on the command's stderr.
- **Pull request:** [#29](https://github.com/nemesis398/phyllon/pull/29).
