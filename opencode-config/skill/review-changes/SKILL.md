---
name: review-changes
description: Use when asked to review, audit or give an opinion on changes that are already written — a working tree diff, a commit, a branch, a PR, or "what do you think of this". Covers reading the real diff instead of remembering it, verifying every claim a comment makes against the thing it claims to describe, finding the places that should have changed with it and did not, checking a change against the rules of the file it lands in, and reporting findings ranked by severity with verified and unverified kept apart. Not for writing code — for judging code that exists. Triggers in Spanish too: "audita los cambios", "revisa el diff", "revisa lo que cambie", "que te parece este cambio", "estan bien estos cambios", "revisa esta rama".
---

# Review changes

You are judging code that already exists. The failure mode here is not writing a
bad line — it is **declaring something correct because it looked correct**.

A review has exactly one deliverable: a list of findings, each one either
verified against a source you can name, or explicitly labelled as not verified.
Anything else — a summary of what the diff does, praise, a restatement of the
commit message — is padding. The user can read the diff; what they cannot do
cheaply is check every claim in it.

## 0. Read the diff NOW. Never from memory.

First tool call, always, before any opinion:

```bash
git status --porcelain && git diff && git diff --cached && \
  git ls-files --others --exclude-standard
```

Four things, because a change hides in any of them: unstaged, staged, untracked
files, and a `.gitignore` that decides what you are even allowed to see.

**The diff you read three turns ago is not the diff.** The user edits files
while you work. If you are asked to review "again", or any time has passed, run
the command again before saying anything — including before saying "nothing
changed". Comparing `git diff --stat` against what you remember is how you end
up auditing a file that no longer exists in that form.

For other targets:

| target | command |
| --- | --- |
| last commit | `git show HEAD` |
| a branch vs main | `git diff main...HEAD` |
| a PR | `gh pr diff <n>` |
| "since yesterday" | `git log --oneline -20` first, then pick a range |

## 1. A comment is a claim. The code is the evidence.

The single highest-yield move in a review: take every factual assertion the diff
makes about something outside itself, and go look at that thing.

Assertions worth chasing, in order of how often they turn out wrong:

- **"Verified against X"**, "checked with Y", "source: Z" — the most dangerous,
  because it reads like the check already happened. It happened *once*, maybe
  years ago, against a version that has moved. Go read X.
- **A name from another system**: a tool name, an API parameter, a config key,
  an env var, a model id, an endpoint. Find where it is *defined*, not where it
  is mentioned.
- **A number**: a limit, a timeout, a context size, a benchmark figure. Where
  does it come from, and does the source still say that?
- **A negative**: "this does not exist", "it does not support", "it is not
  possible". Negatives are wrong more often than positives and nobody rechecks
  them.

How to chase one, cheapest first:

```bash
grep -rn "<the exact name>" <the other repo or dir>   # the definition, not a mention
curl -s <the endpoint> | head                          # the server, not the doc about it
<cmd> --help | grep -i <flag>                          # the tool, not your memory
```

If you cannot check it from this machine, that is a finding too — write
`no verificado` and say what would verify it. A precise "unknown" is worth more
than a confident guess, and much more than silence.

## 2. What the diff touched vs. what it should have touched

Most real bugs in a reviewed change are not in the diff. They are in the file
that says the same thing and was **not** updated.

For every identifier the diff renames, adds or removes, ask where else that
identifier lives:

```bash
grep -rn "<the old name>" . --exclude-dir=.git      # who still says the old thing
grep -rn "<the new name>" . --exclude-dir=.git      # is it consistent everywhere
```

Then check the usual suspects by hand: README, docs, comments in the config,
tests, Makefile targets, CI, example files. A change that fixed a name in two
of three places has not been made — it has been split, and the third place is
now a booby trap for whoever reads it next.

## 3. Check the change against the rules of the file it lands in

Read enough of the surrounding file to know its conventions, then hold the diff
to them:

- Does the file say instructions are in one language and the new block uses
  another? Does it fix a phrasing in one place and a different phrasing for the
  same thing three sections up?
- Does the new text contradict a rule stated earlier in the same file? *Two
  instructions for the same decision is worse than none* — especially for a
  small model, which will average them into a third behaviour nobody wrote.
- Is the same fact now specified in two places? Duplication is not a style
  complaint here: it is the mechanism by which the two copies drift. When you
  find a contradiction, the finding is not just "these disagree", it is "these
  disagree *because* the fact is stored twice".
- Did the diff land between a comment and the thing that comment describes?

## 4. Also look for what nobody deleted

- Dead config: an entry that no longer resolves, a flag nothing reads, a model
  id that 404s.
- A value that is now a no-op because a higher-priority setting overrides it.
- A rule justified by a constraint that no longer exists.

These never break a build, so nothing else will catch them.

## 5. Report

Ranked by severity, most severe first. For each finding:

1. **Where** — `path:line`.
2. **What is wrong** — one sentence, concrete.
3. **How it fails** — the input or situation that makes it bite. If you cannot
   describe the failure, it is a preference, not a finding: drop it or label it
   as taste.
4. **The evidence** — the command you ran, the `file:line` you read, the HTTP
   response you got. No evidence → label it `no verificado`.

Rules for the report:

- **Verified and unverified never share a bullet.** Mixing them makes the whole
  list unusable, because the reader cannot tell which half to trust.
- **Say what is right, briefly.** If the risky part of the change is actually
  correct and you checked it, one line saying so — with the evidence — is real
  information and stops the user re-checking it.
- **No severity inflation.** A style nit dressed as a bug costs you the reader's
  attention for the real one. Three findings that matter beat eleven that fill a
  page.
- End with what you would fix first, and stop. Reviewing is not fixing: do not
  edit anything unless the user asked for the fixes too.

## 6. The three ways this review goes wrong

1. **You reviewed a stale diff.** You answered from what you read earlier, the
   user had edited since, and half your findings were about lines that no longer
   exist. Re-read (§0). This has actually happened.
2. **You trusted a "verified" comment.** It said it had been checked against the
   server, so you passed it. The server had grown six tools since. A claim is
   not evidence just because it is written in the imperative (§1).
3. **You graded the diff instead of the change.** Every line in the diff was
   fine, and the change was still broken, because the same name lives in a
   README, a Makefile and a test that nobody touched (§2).
