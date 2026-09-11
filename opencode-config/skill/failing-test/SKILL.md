---
name: failing-test
description: Use when a test fails, a suite goes red, CI is failing, or you are tempted to skip, ignore, delete or loosen a test to get a green build. Gives how to read the failure, how to decide whether the code or the test is wrong, the minimal fix, and what to do when you cannot fix it. Use ALSO when the environment blocks an edit that adds t.Skip / it.skip / @pytest.mark.skip. Triggers in Spanish too: "el test falla", "esta en rojo", "no pasan los tests", "salta este test", "ponlo en verde".
---

# A failing test

A red test is information you paid for. The only outcomes allowed are: **the
code gets fixed**, **the test gets corrected for a stated reason**, or **you
report it and leave it red**.

Never the fourth one. Skipping, ignoring, deleting, commenting out, wrapping in
`try/except`, or loosening an assertion until it passes does not fix anything —
it hides the defect behind a green build, which is *worse* than a red one,
because now nobody will look again. The environment blocks these edits on
purpose.

## 1. Read the whole failure, not the last line

```bash
<test command> 2>&1 | tail -60
```

You need four things, and they are usually all there:

- **which** test failed (name and file:line),
- **expected vs actual** — write both down,
- the **stack trace's first frame inside your own code**, not the framework's,
- whether it is one test or all of them. All of them failing = setup, imports,
  config or environment. One = logic.

Run only the failing test while you work — the loop is faster and the output is
readable:

```bash
go test ./... -run 'TestName' -v      # go
npx vitest run -t "name"              # vitest/jest
pytest path/to/test_x.py::test_name -x -q
cargo test test_name -- --nocapture
```

## 2. Decide who is wrong: the code or the test

This is the whole decision, and it has an actual criterion — **what does the
requirement say?** Not "which is easier to change".

**The code is wrong** (the usual case) when the test states what the user or
the spec asked for and the code does something else. Fix the code.

**The test is wrong** only when you can finish this sentence out loud: *"the
test asserts X, but the correct behaviour is Y, because \<requirement\>."*
Typical legitimate cases: the requirement changed in this same task; the test
encodes an implementation detail you were explicitly asked to change; the test
itself has a bug (wrong fixture, wrong date, off-by-one in the expectation).

Then change the assertion to **what is correct** — never to whatever the code
currently returns. Copying the actual output into the expectation is the same
sin as skipping, with extra steps.

If you cannot say which, the code is wrong. Assume the test.

## 3. Fix it small

- Change the smallest thing that makes the test pass **for the right reason**.
- Do not rewrite the module, do not "improve" neighbours, do not reformat.
- Re-run the single test, then the whole suite. Both.
- A fix that makes another test fail is not a fix. Read that one too.

## 4. Flaky, slow or environment-dependent

If it fails only sometimes, or only here: say so explicitly and name the cause
(a real clock, a real network call, a port, an ordering assumption, a shared
temp dir). That is a defect in the test and it has a real fix — inject the
clock, fake the call, pick a free port, isolate the fixture. `t.Skip` is not a
fix, it is a way of forgetting.

## 5. When you cannot fix it

Leave it red and report — one line of the exact failure, what you ruled out,
and what you would need:

> `TestPayment/refund` fails: expected `status=refunded`, got `pending`. The
> refund path calls the provider stub, which returns `pending` for any amount
> over 100. Fixing it properly means the stub needs the amount-based branch; I
> did not change the test because `refunded` is what the requirement asks for.

That is a good hand-off. A green suite that lies is not.
