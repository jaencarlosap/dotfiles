---
name: dependencies
description: Use when adding, upgrading, pinning or removing a third-party package, when an import fails because something is not installed, or when picking between libraries. Covers checking what is already installed before adding anything, using the package manager instead of hand-editing manifests or lockfiles, getting the real current version instead of inventing one, and verifying the install actually works. Triggers in Spanish too: "instala", "añade la dependencia", "actualiza la libreria", "que version uso", "no encuentra el modulo".
---

# Dependencies

Two rules cover almost every failure here: **never write a version number from
memory**, and **never hand-edit a manifest or a lockfile**.

Both are the same mistake — inventing state that a command could have told you.
A wrong version in `package.json` fails at install time; a hand-edited lockfile
fails later, weirdly, on someone else's machine.

## 1. Is it already there?

Adding what already exists is how a project ends up with two HTTP clients and
two date libraries.

```bash
grep -rn "<pkg>" package.json go.mod pyproject.toml Cargo.toml requirements*.txt 2>/dev/null
ls node_modules/<pkg> 2>/dev/null; pip show <pkg> 2>/dev/null; go list -m all 2>/dev/null | grep <pkg>
```

Also ask whether you need it at all: the standard library, or a package already
in the tree, usually covers it. Extending what exists beats adding a dependency.

## 2. What is the real current version

```bash
docs.sh npm <pkg>      # version, repo, whether it ships types, deps
docs.sh py <pkg>       # version, required python, docs
docs.sh rs <crate>     # version, docs.rs
docs.sh go <module>    # latest published versions
```

That is one call and it is the truth. Your memory of "^4.2.0" is not.

## 3. Let the package manager write the manifest

```bash
npm install <pkg>            # or: npm install -D <pkg> for dev-only
go get <module>@latest && go mod tidy
uv add <pkg>                 # or: pip install <pkg> && pip freeze > requirements.txt
cargo add <crate>
```

The manager resolves the range, updates the lockfile and the manifest
consistently. You cannot do that by hand and you should not try. If a command
you are unsure about exists, `--help` first.

## 4. Verify it landed — the import, not the file

```bash
node -e "require('<pkg>')" && echo OK
python3 -c "import <pkg>; print(<pkg>.__version__)"
go build ./... && echo OK
```

Installed and importable are different things: wrong workspace, wrong venv,
wrong Go module, ESM vs CJS. Prove the import.

## 5. Then use the API of the version you installed

This is where a small model burns a task: writing calls from memory that belong
to another major version. Check the version you actually have, then read the
signature from disk or from the docs **for that version**:

```bash
grep -rn "<symbol>" node_modules/<pkg>/dist/*.d.ts | head    # types = signatures
go doc <module>.<Symbol>
python3 -c "import <pkg>; help(<pkg>.<thing>)"
```

If it is not on disk, that is `web-research` — and read the docs for **your**
version, not the latest release.

## 6. Upgrades and removals

- Upgrading: read the CHANGELOG or migration guide for the majors you cross
  (`web.sh search "<pkg> migration <old> to <new>"`), then run the tests. An
  upgrade with no test run is not done.
- Removing: `npm uninstall` / `go mod tidy` / `uv remove`, then grep for
  leftover imports. A package removed from the manifest but still imported is a
  broken build waiting for the next clean checkout.
- Never commit a lockfile change you did not cause.
