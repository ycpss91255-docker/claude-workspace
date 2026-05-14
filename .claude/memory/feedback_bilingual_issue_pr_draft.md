---
name: bilingual-issue-pr-draft
description: "For issue and PR bodies, draft in zh-TW first and present for user review, then translate to English only when actually invoking `gh issue create` / `gh pr create`. The CJK-block hook prevents direct Chinese submission anyway, so the English version is just the submission artifact -- the source of truth for review is the Chinese draft."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 57c42783-dd59-4158-905a-b8d90ffa7347
---

For `gh issue create` and `gh pr create`, do not jump straight to writing the body in English. The workflow is:

1. **Draft in zh-TW** in `/tmp/<name>-zh.md` (or similar) so the user can review in their native language.
2. **Show the Chinese draft inline in chat** for review. User may ask for edits, scope changes, additions.
3. **On user approval**, translate the approved Chinese draft to English, save as `/tmp/<name>.md` (or overwrite the zh file), then `gh ... --body-file <english.md>`.
4. The CJK-block hook (`remind_no_chinese_in_git_artifacts.sh`) BLOCKs Chinese in the actual `gh` invocation, so step 3 is non-optional -- but the SOURCE OF TRUTH for what the issue / PR is saying is the Chinese draft the user reviewed, not the post-translation English.

**Why:** User reviews more accurately in zh-TW than English. Issues and PRs commit to scope, so a mistranslation or over-eager edit during English-write-from-scratch can land the wrong content. Drafting in Chinese first preserves the user's intent.

**How to apply:**
- Applies to `gh issue create` and `gh pr create` bodies (long-form).
- Does NOT apply to: titles (kept short and English from the start), commit messages (English from the start per CJK-block rule), code comments, README content.
- For PR bodies: still follow the existing 5-section structure (Summary / etc.) but write the sections in Chinese first.
- Trivial 1-line issue bodies can skip the draft step if the user already specified the content verbatim.

Established 2026-05-14 after observing #92/#93/#94/#95 issues were opened directly in English without intermediate Chinese review.
