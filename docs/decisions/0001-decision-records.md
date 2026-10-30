# 0001: Decision records

Date: 2026-10-29

Status: accepted

## Context

Phyllon is built by one maintainer and many AI agents, and an agent starts each
session without the memory of the last. A call made once, such as a package
layout or a choice of web framework, is questioned again each time a new reader
meets it, and the reasons are then lost in a pull request thread or a chat. The
project needs one place where such a call is written down with its reasons and
the options that lost.

## Options

1. **One file per decision** in `docs/decisions/`, named `NNNN-slug.md`, with a
   fixed set of sections.
2. **One log file** with a dated entry per decision.
3. **No records**, with the reasons left in pull request descriptions and the
   commit history.

The comparison uses the five dials of the conscience skill: granularity (can a
coarse unit be replaced by finer ones), redundancy (how many paths reach the
same effect), coupling (does using one thing secretly obligate another),
retention (does the interface keep its own copy of your data that you must keep
in sync) and flow control (who calls whom). Retention and flow control do not
bite on a documentation format, so the table marks them "not at stake" instead
of stretching them.

| Dial         | One file per decision                                             | One log file                                            | No records                                               |
| ------------ | ----------------------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------- |
| Granularity  | One decision per file, so one can be read or linked alone         | One coarse file, and one decision cannot be taken alone | None                                                     |
| Redundancy   | One place per decision, though a summary may repeat a design      | One place, but the log grows into a second design       | Each pull request restates its reasons, in its own words |
| Coupling     | A record names the one it supersedes, and that one changes status | Entries depend on their order in the file               | The reasons depend on a thread on a host                 |
| Retention    | Not at stake                                                      | Not at stake                                            | Not at stake                                             |
| Flow control | Not at stake                                                      | Not at stake                                            | Not at stake                                             |

## Decision

Use option 1. Each decision gets its own file in `docs/decisions/`, named
`NNNN-slug.md`, where `NNNN` is the next free four-digit number and the slug is
a few lowercase words joined by hyphens.

A record holds, in this order:

1. A title: the number and a short name.
2. A date and a status line. The status is `accepted` or `superseded by NNNN`.
3. **Context**: the forces and facts that made a decision necessary.
4. **Options**: the realistic choices, each in a line or two. When the choice
   has real trade-offs, compare the options in a table on the five dials:
   granularity, redundancy, coupling, retention and flow control, and write "not
   at stake" for a dial that does not bite.
5. **Decision**: the option chosen, stated as an instruction.
6. **Consequences**: what becomes easier, what becomes harder, and what to
   revisit.

A record is not edited after it is accepted, except to set its status. A changed
mind is a new record that supersedes the old one, and the old record then says
`superseded by NNNN`.

## Consequences

- A reader can find why something is the way it is without reading the history.
- Each record costs a short document. Write one only for a call that a later
  contributor might question, not for each change.
- `docs/map.md` links the records behind each module, so a record has to stay at
  a stable path, and a superseded one stays in place.
- This record is the first, and it is in the format it describes.
