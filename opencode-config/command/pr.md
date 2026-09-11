---
description: Verify, commit the change on a branch, and open a pull request
agent: auto
---

Ship the current change as a pull request. Extra context / PR focus: $ARGUMENTS

Do these steps in order and STOP at the first one that fails:

1. **Verify first.** Run the project's build + tests (as in `/verify`). If it
   is not green, do NOT commit — report the failure and stop. Never open a PR
   on red.
2. **Inspect what changed.** `git status --short` and `git diff --stat`. If
   there is nothing to commit, say so and stop.
3. **Branch if needed.** If on the default branch (`main`/`master`), create a
   descriptive branch: `git switch -c <type>/<short-slug>`. Never commit
   straight to the default branch.
4. **Commit.** Stage the relevant files (not stray/scratch files) and write a
   Conventional-Commits message: `<type>(<scope>): <imperative summary>`, with
   a short body explaining WHY if it is not obvious. One logical change per
   commit.
5. **Push.** `git push -u origin HEAD`. (This may hit the `git push` permission
   prompt — that is expected; wait for approval.)
6. **Open the PR** with `gh pr create`, title = the commit summary, body =
   what changed and how it was verified. Print the PR URL.

Report the branch name, commit hash, and PR URL when done.
