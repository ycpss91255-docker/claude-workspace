---
description: Create a new Architecture Decision Record (ADR) in the current repo's doc/adr/. Use when a design discussion lands a non-actionable rationale conclusion that doesn't fit any other artifact (commit / PR / issue / CLAUDE.md).
argument-hint: <slug>
---

# /adr <slug>

Create a new Architecture Decision Record (ADR) in `doc/adr/`.

ADRs capture **why** a design decision was made, with enough context
that a future reader can understand the trade-offs without
re-deriving them. Pair with the `remind_adr_on_design_decision.sh`
Stop hook (issue #97) which nudges this command when a session
shows rationale-shaped discussion but landed no ADR.

## When to use

- A design discussion concludes with a clear "we chose X over Y"
  decision that does **not** fit any other artifact slot:
  - Not a code change -> not appropriate for commit / PR body.
  - Not a standing rule -> not appropriate for CLAUDE.md (would
    bloat over time).
  - Not an actionable issue -> not appropriate for `gh issue create`.
- Examples: "use single entrypoint.sh instead of multi-entrypoint
  folder", "X bump is ceremonial, decoupled from breaking changes",
  "treat SKIPPED as success-equivalent in wait-pr-ci".

If the conclusion is "let's fix this bug" -> use `/pr`, not `/adr`.
If the conclusion is "this is the rule for future work" -> consider
CLAUDE.md prose. ADRs are for *historical rationale*, not standing
rules.

## Steps

1. Pick a kebab-case slug that summarises the decision in 1-5
   words. Examples: `entrypoint-single-file`,
   `semver-x-ceremonial`, `skipped-as-success`.
2. Run `.claude/scripts/new-adr.sh <slug>`. The script:
   - Auto-picks the next number (8-digit zero-padded) by scanning
     `doc/adr/[0-9]*.md`.
   - Creates `doc/adr/NNNNNNNN-<slug>.md` with the 5-section
     template: Date / Status / Context / Decision / Alternatives /
     Consequences.
   - Status defaults to `Accepted`. Flip to
     `Superseded by ADR-NNNNNNNN` on the old entry when a later
     ADR replaces it. **Numbers are never reused.**
3. Fill in each section. Be concrete: name the alternatives
   considered, capture the trade-offs that drove the choice, list
   the costs you accepted.
4. `git add doc/adr/NNNNNNNN-<slug>.md && git commit -m "docs(adr):
   ADR-NNNNNNNN <one-line>"`.
5. (Optional) Push as part of an existing PR, or open a `docs:` PR
   if the decision warrants reviewer eyes.

## Numbering and placement

- **Per-repo `doc/adr/`.** Most ADRs are repo-specific (`base`'s
  entrypoint decision does not belong in `docker_harness`).
- **8-digit zero-padded.** `00000001`, `00000002`, ... Wide padding
  lets future stream-merge / bulk reorganisation happen without
  renumbering existing entries.
- **Numbers never reused.** Superseded ADRs stay in place;
  cross-link via `Status: Superseded by ADR-NNNNNNNN` on the old
  one.

## Status enum

| Status | When |
|---|---|
| `Accepted` | Default. The decision is in effect. |
| `Proposed` | Drafted but not yet ratified (rare in this org). |
| `Deprecated` | Decision no longer applies but has no replacement yet. |
| `Superseded by ADR-NNNNNNNN` | Replaced by a newer ADR. Cross-link in both directions. |

## Out of scope

- **Cross-repo global ADR index.** Per-repo `doc/adr/` is enough;
  no central aggregation site.
- **Mandatory ADR review process.** ADRs go through normal PR
  review; no extra approval workflow.
- **Backfilling existing CLAUDE.md rationale blocks.** Defer; can
  be a separate cleanup pass once the convention beds in.

## References

- `.claude/scripts/new-adr.sh --help`
- `.claude/hooks/remind_adr_on_design_decision.sh` -- Stop hook
  that nudges this command after rationale-shaped sessions
- ADR-00000001 in this repo -- meta entry recording the convention
- Michael Nygard 2011 ADR template -- the 4-section
  Context/Decision/Status/Consequences pattern this command
  extends with an explicit Alternatives section
