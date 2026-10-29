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

The comparison uses the five dials of the conscience skill: how fine the unit
is, how much is stated twice, how tightly the parts depend on each other, how
long the record stays useful, and how much it steers the next change.

| Dial         | One file per decision                          | One log file                                 | No records                           |
| ------------ | ---------------------------------------------- | -------------------------------------------- | ------------------------------------ |
| Granularity  | One decision per file, linkable from code      | Many decisions in one file, linked by anchor | None                                 |
| Redundancy   | A summary may repeat a fact from the design    | Same, and the log grows into a second design | Reasons repeat in each pull request  |
| Coupling     | A record links to the ones it replaces         | Entries depend on their order in the file    | Reasons tied to a thread on a host   |
| Retention    | A superseded record stays, marked, and is kept | Old entries blur into the new ones           | Lost when the thread is hard to find |
| Flow control | A map entry or a review can cite the number    | A review must quote a passage                | A reviewer must ask again            |

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
   granularity, redundancy, coupling, retention and flow control.
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
