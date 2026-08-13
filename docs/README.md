# Documentation

Everything that describes Drive OSX, arranged by the question it answers.

**New here? Read [overview.md](overview.md) first** — ten minutes, and it
prevents most of the mistakes the guide below lists.

## Layout

```text
docs/
├── overview.md              What the system is, end to end
├── architecture.md          How it is actually built
├── architecture/
│   └── decisions/           ADRs — why a choice was made, and what breaks if reversed
├── guides/
│   ├── developer-guide.md   How to change this repository without breaking it
│   └── testing.md           How to verify a change, and where coverage is missing
├── reference/
│   ├── applications.md      Every application and its real status
│   └── integration-map.md   What talks to what, and what breaks if you change it
├── features/                One document per feature, end to end
└── status/                  Point-in-time audits and verification reports
```

Two documents live outside this folder on purpose:

| File | Why it stays at the root |
| ---- | ------------------------ |
| [CLAUDE.md](../CLAUDE.md) | The standing brief — principles and long-term direction. Coding agents read it automatically from the repository root. |
| [README.md](../README.md) | The repository entry point: what this is and how to run it. |

## By question

| You want | Read |
| -------- | ---- |
| To understand the system before changing it | [overview.md](overview.md) |
| To know how it is built | [architecture.md](architecture.md) |
| To change code safely | [guides/developer-guide.md](guides/developer-guide.md) |
| To know whether an application actually works | [reference/applications.md](reference/applications.md) |
| To know what your change breaks downstream | [reference/integration-map.md](reference/integration-map.md) |
| To verify a change | [guides/testing.md](guides/testing.md) |
| To know why something was done this way | [architecture/decisions/](architecture/decisions/) |
| To follow one feature end to end | [features/](features/) |
| To know what is broken or missing | [status/audit-and-plan.md](status/audit-and-plan.md) |

## Feature guides

| Feature | Document |
| ------- | -------- |
| Windows, dragging, resizing, dock visibility | [features/shell-windows-and-dock.md](features/shell-windows-and-dock.md) |
| Direct messaging, chat requests, contacts, presence | [features/messaging-and-contacts.md](features/messaging-and-contacts.md) |

## Status documents

`status/` holds **point-in-time snapshots**, not living documents. Each is
dated in its header and describes the repository as it was on that date.

| Document | What it is |
| -------- | ---------- |
| [status/audit-and-plan.md](status/audit-and-plan.md) | The audit that produced the `TASK-nnn` identifiers used throughout the other documents. Deferred tasks are still tracked here. |
| [status/verification-report.md](status/verification-report.md) | A whole-repository verification pass, with an explicit basis for every claim. |

The two overlap: they were written a day apart over the same scope. The audit
is the one to update when a defect is found or fixed — the verification report
is a record of a particular pass and should be read as history.

## Conventions

* Filenames are lower-case and hyphenated. `ADR-*.md` is the one exception:
  decision records are numbered and their names are referenced elsewhere.
* Every claim about whether something works carries its basis — `VERIFIED`,
  `REVIEWED`, `UNKNOWN`, `BLOCKED`. There is **no browser automation in this
  repository**, so no document may claim that a user interface works on any
  stronger basis than typecheck, build, and the API calls the code makes. The
  reasoning behind this rule is in
  [guides/developer-guide.md](guides/developer-guide.md#reporting-honestly).
* Documentation is updated in the same change as the code, not afterwards. The
  table of what to update for what is at the end of the developer guide.
