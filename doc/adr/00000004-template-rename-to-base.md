# ADR-00000004: Rename `template` GitHub Repo to `base`; Defer Local Folder Rename

- **Date:** 2026-05-20
- **Status:** Accepted (rename done; local folder rename deferred)

## Context

Until early 2026, the shared scaffolding repo for the
`ycpss91255-docker` organisation was named `template`. The name
predated the multi-repo split and reflected the original intent:
"clone this template, fill in the Dockerfile, rename `image_name`".

The rename came up after two repeated points of confusion:

1. **`git subtree --prefix=` is `.base/`, not `template/`.** Every
   downstream repo has a `.base/` directory holding the squashed
   subtree. The remote that drives it being called `template` made
   the relationship ungrep-able: a contributor reading downstream
   Dockerfile lines like `COPY .base/script/docker/setup.sh ...`
   could not jump from `.base` to the source by name. Renaming the
   remote to `base` makes the chain
   `.base/ -> ycpss91255-docker/base` self-documenting.
2. **The "template" word implied one-shot bootstrap.** Several
   contributors assumed the repo was for `init.sh` to copy from
   once, then discard. In reality the relationship is a permanent
   subtree dependency; `make upgrade` pulls new versions throughout
   the downstream's lifetime. "Template" misnames the relationship.

GitHub's repo-rename feature handles the redirect transparently:
old URLs / clones / forks keep working, and links auto-redirect to
the new name. The cost of renaming is essentially zero on GitHub's
side.

## Decision

Rename the GitHub repo from `ycpss91255-docker/template` to
`ycpss91255-docker/base`.

**Defer renaming the local checkout folder.** The local
`<workspace>/template/` directory continues to be a clone of the
(now-renamed) `ycpss91255-docker/base` repo. Reasons for the
deferral:

- `<workspace>/template/` is referenced by many open worktrees,
  `make` rules, and shell history. Renaming it forces every
  contributor with a worktree open to fix their environment.
- The deferral is observable: contributors see `template/` locally
  but `ycpss91255-docker/base` on GitHub. CLAUDE.md notes this
  asymmetry in its directory-tree listing.
- A separate one-off PR can land the local rename later, when
  there are no urgent open worktrees and we can announce a
  one-shot break to active contributors.

## Alternatives

Two alternatives were considered and rejected:

1. **Keep the name `template`.** Rejected: the two confusion
   points above persist, and they cost more aggregate
   contributor-minutes per month than a one-time rename costs.

2. **Rename the GitHub repo AND the local folder atomically in
   the same PR.** Rejected: the local folder rename is a manual
   step for every contributor with an active checkout. Pushing
   that synchronously with the GitHub rename creates an
   unnecessary coordination burden. The two pieces are
   independent (GitHub redirects handle the gap), so they can
   land separately.

## Consequences

- **GitHub repo URL changes**: `ycpss91255-docker/template` ->
  `ycpss91255-docker/base`. Old URLs auto-redirect; no broken
  links.

- **Subtree remote URL change**: existing checkouts may have
  `template` in their git remote config. `git fetch` continues
  to work via GitHub redirect, but contributors can update via
  `git remote set-url`.

- **Documentation references**: README / CLAUDE.md / CONTEXT.md
  still contain "template" in places where the local-folder
  name is meant. Those references are intentionally preserved
  until the local rename happens.

- **Subtree `git subtree pull --prefix=.base` URL**: the
  documented form uses the new `base` URL. Old `template` URLs
  in cached scripts auto-redirect.

- **Follow-up**: a one-off PR will rename
  `<workspace>/template/` -> `<workspace>/base/` and update all
  references atomically. That PR is tracked separately and is
  not blocked by this ADR.

## References

- Issue ycpss91255-docker/docker_harness#119 (this ADR's
  tracking issue; Tier 1 of #116).
- `<workspace>/template/` directory listing in CLAUDE.md
  (preserves the deferred-rename note).
- GitHub repo-rename docs (redirect semantics).
