# ADR-00000003: Single `CONTEXT.md` for Domain Knowledge (Not `doc/claude/*` Multi-File)

- **Date:** 2026-05-20
- **Status:** Accepted

## Context

`CLAUDE.md` had grown to ~930 lines by 2026-05. Every Claude Code
session loads it into the system prompt, so the file's size is
real cost: longer prompt = more tokens billed every turn + more
material the agent must hold in working memory.

A 64-section audit in issue #116 classified the contents into five
buckets:

| Class | What it is | What should happen |
|---|---|---|
| A | Already covered by an existing hook | Delete from CLAUDE.md (hook is source of truth) |
| B | Already covered by an existing skill | Delete from CLAUDE.md (skill is source of truth) |
| C | Domain knowledge / reference material | **Move to a separate file** |
| D | Standing rule (must / never / always) | Keep in CLAUDE.md |
| E | Workflow contract / process discipline | Convert to a new enforcement hook (E1 = skill, E2 = hook) |
| F | Directory tree listing / pointers | Keep in CLAUDE.md |

Class C accounts for 28 of the 64 sections — clearly the largest
single migration target. The question this ADR settles: **where
does class C go?**

Issue #112 originally proposed an 8-file split under `doc/claude/`
(`architecture.md`, `scripts-catalog.md`, `bash-parser-pitfalls.md`,
`sandbox-setup.md`, `design-patterns.md`, `release-process.md`,
`memory-setup.md`, `postmortems.md`). Issue #112 was closed in
favour of #116, which switched the structural choice to a single
`CONTEXT.md` file. This ADR records that decision so future
contributors can find the rationale without grep-ing closed-issue
comments.

## Decision

Class C content lives in a **single `CONTEXT.md`** at repo root,
with 13 sections covering naming, container architecture, setup
pipeline, subtree mechanics, CI/CD, versioning, i18n, defaults,
agent credentials, branch protection, TDD matrix, Docker-only
verification, and known gotchas.

A top-of-file disclaimer documents the three-way routing:

| Looking for... | Read |
|---|---|
| Standing rule | `CLAUDE.md` |
| Domain knowledge | `CONTEXT.md` |
| Historical decision | `doc/adr/NNNNNNNN-*.md` |

This makes the file's purpose unambiguous: it is the *reference
manual*, not the *rules-of-engagement* (CLAUDE.md) and not the
*decision log* (ADRs).

Access pattern: agents view `CONTEXT.md` on-demand via `Read` /
`grep`, not via `@import`. CLAUDE.md keeps a one-line pointer to
this file under the relevant standing-rule sections (e.g. the
TDD section in CLAUDE.md points at `CONTEXT.md` section 11 for
the full matrix; the SemVer pointer goes to section 6).

## Alternatives

Three alternatives were considered and rejected:

1. **`doc/claude/*.md` multi-file split** (#112's original).
   Rejected for three reasons:
   - **Discoverability cost.** A contributor looking up "what's
     the setup.conf schema" has to first scan
     `doc/claude/README.md` to find the right file, then open
     that file. Single-file lets `grep '## 3.' CONTEXT.md` jump
     straight there.
   - **`postmortems.md` would be free-form.** #112's plan had a
     dedicated postmortems file; per ADR-00000001, historical
     rationale belongs in structured ADRs with the 5-section
     template, not a free-form table.
   - **8 files is a lot of moving parts to maintain.** Each file
     needs its own cross-link discipline, its own header, its own
     "what doesn't belong here" boundary. Single file collapses
     all of that.

2. **`@import CONTEXT.md` from `CLAUDE.md` (always inline).**
   Rejected: defeats the purpose. Inlining `CONTEXT.md` into
   every session's system prompt is identical, cost-wise, to
   keeping the content in CLAUDE.md directly. The whole point
   is to keep CLAUDE.md *small*.

3. **`@import CONTEXT.md` on-demand.** Rejected: the on-demand
   semantics of `@import` are uncertain (Claude Code resolves
   `@import` at load time, not at view time, so "on-demand" is
   not a thing the import mechanism gives us). Plain `Read`
   already provides on-demand access; no new mechanism needed.

## Consequences

- **CLAUDE.md can shrink.** Sub-issue #127 (Tier 4 of #116) will
  delete the migrated content from CLAUDE.md and replace it with
  one-line pointers into the matching `CONTEXT.md` section. The
  240-line ceiling target (down from ~930) becomes feasible.

- **New file at repo root.** `CONTEXT.md` lives next to
  `CLAUDE.md` and `README.md`. New contributors discover it via
  ls / GitHub auto-render at the repo root.

- **No new tooling.** The file is plain markdown read via
  existing `Read` / `grep` flows. No `@import` semantics to
  reason about, no preprocessor, no schema.

- **Single-file means single-file conflicts.** Two parallel
  edits to `CONTEXT.md` will need merge resolution. Class C
  content changes slowly (it tracks repo architecture, not
  features), so this is expected to be rare in practice. If it
  becomes a problem, splitting individual sections out into
  their own files is a one-way ratchet — easy later, hard to
  undo a multi-file split.

- **Per-incident rationale goes to ADRs, not `postmortems.md`.**
  This makes ADR-00000001's convention the canonical resting
  place for historical decisions, removes a structural ambiguity
  (was an incident a "postmortem" or an "ADR"?), and reuses the
  existing 5-section template instead of inventing a second
  format.

## References

- Issue ycpss91255-docker/docker_harness#118 (this ADR's
  tracking issue; Tier 1 of #116).
- Issue ycpss91255-docker/docker_harness#116 (umbrella; lists
  the slim plan + 64-section classification).
- Issue ycpss91255-docker/docker_harness#112 close comment
  (the structural-choice trade-off summary that led to this
  ADR being filed).
- `doc/adr/00000001-why-adr.md` — the meta-ADR establishing the
  convention; `postmortems.md` rejection consistent with that
  convention.
- `CONTEXT.md` — the file created by this decision.
