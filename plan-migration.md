# Dotfiles Migration & Fix Plan

Status of the repo: a half-finished migration. The bash scripts (`clean_system.sh`,
`burn-iso.sh`, `dotfiles.sh`, `setup_nvim.sh`) still exist alongside a Go TUI
(`dtool/`) that already re-implements all of their functionality with Bubble Tea
+ Lipgloss. The plan below finishes that migration and fixes the real bugs in
the Go side.

**Hands-off rule for the shell scripts:** the original `.sh` files are *not*
modified during this migration. They get moved verbatim into `older_scripts/`
as a fallback. They stay there until **you** verify the Go tool works for each
flow on your machine, and only then do you delete them yourself. The plan
never deletes them.

---

## 1. Language choice

**Recommendation: stay on Go.** The migration is already underway, builds cleanly
(`go build` passes, `go vet` is clean), and Go gives us a single static binary,
zero runtime dependency on the user's shell, and a TUI ecosystem
(`charmbracelet/bubbletea`, `lipgloss`, `bubbles`) that is already wired up.

For completeness, alternatives considered:

| Option        | Pros                                               | Cons                                                            | Verdict |
|---------------|----------------------------------------------------|------------------------------------------------------------------|---------|
| **Go (current)** | Single binary, great TUI libs, already started   | None for this scope                                              | **Keep** |
| Rust + ratatui   | Strong typing, fast                              | Doubles the work; longer compile; no benefit for this scope     | Skip |
| Python + Textual | Fast to write                                    | Requires runtime; `pip` setup contradicts the "dotfiles" goal   | Skip |
| Pure Bash (current scripts) | Zero install                            | Quoting/globbing bugs, no testing, hard to evolve               | Retire |

We'll keep one tiny shell entry point (`dotfiles`) only if needed for
bootstrapping (`go install` / `brew install`). The original scripts are
preserved untouched in `older_scripts/` as a fallback until the user
confirms the Go ports work and removes them by hand.

---

## 2. Bugs found (confirmed)

### Shell scripts (documented for reference — **not** touched by the plan)

The originals are preserved verbatim in `older_scripts/`. The bugs below are
listed only so the Go ports can fix them; the `.sh` files themselves stay
as-is.

1. **`setup_nvim.sh:6`** — points to `$(pwd)/nvim`, but the actual config
   directory is `nvim-config/`. The symlink target doesn't exist, so the script
   fails immediately on a clean machine.
2. **`burn-iso.sh:38`** — uses `${IMG_PATH}.dmg` because `hdiutil convert` adds
   `.dmg` automatically; but `IMG_PATH` was already derived as `*.img`, so the
   final path becomes `name.img.dmg`. Works by accident only if the input
   filename ends in `.iso` — fragile and confusing.
3. **`burn-iso.sh:38`** — `dd` runs without `status=progress` interval and the
   user has no signal of liveness for multi-minute writes. (The flag is
   present, but on macOS `bs=1m` syntax is BSD-only; it works on macOS but
   wouldn't on Linux — consistency matters once this becomes Go.)
4. **`clean_system.sh`** — large, hard to test, mixes globbing, sudo gating,
   and interactive prompts. Not "broken" in the sense of failing, but fragile
   (e.g. `safe_rm "$target"/*` depends on shell glob expansion behavior).
5. **`dotfiles.sh`** — works, but is a one-function shim that is already
   re-implemented in `dtool/pages/git.go`.

### Go TUI (`dtool/`)

1. **`pages/cleaner.go:378, 393`** — calls
   `runner.RunWithSudo("rm", "-rf", dir+"/*")`. `exec.Command` does **not**
   invoke a shell, so `/*` is passed as a literal argument to `rm`, which
   fails with "No such file or directory". This is a real bug; system-cache
   and `/private/tmp` cleanup paths are silently broken.
2. **`runner/runner.go:20`** — `RunWithSudo` does not connect `stdin`/TTY,
   so any sudo password prompt hangs the TUI with no feedback. Needs an
   interactive escape hatch (e.g. ask once at startup, cache via
   `sudo -v`, or shell out to a foreground command).
3. **`pages/git.go:88-90`** — by default *all* non-current branches are
   pre-checked. One stray `enter` and the user nukes every local branch.
   Should default unchecked.
4. **`pages/cleaner.go`** — long scans (`filepath.WalkDir` over `~/Documents`,
   `~/Projects`, etc.) run synchronously inside a `tea.Cmd` with no progress
   indicator beyond "Running..."; on real machines this can take 10+ seconds.
5. **`pages/nvim.go:117-122`** — `brew install <pkg…>` is run as a single
   batched command. If any package is already installed and brew exits
   non-zero (it does on some warnings), the whole task is marked failed even
   though most installs succeeded.
6. **`pages/burner.go:163`** — `dd` is invoked synchronously; the TUI shows
   "Writing image... this may take a while" with no progress. For a 4 GB
   write this looks frozen.
7. **`pages/burner.go:152`** — same `.iso` → `.img.dmg` fragility as the
   shell version.
8. **`pages/cleaner.go:454-460`** — scan directories are hardcoded; the shell
   version lets the user supply custom paths. Regression in the port.
9. **No tests anywhere**, no CI, no lint config.
10. **`makefile:17`** — `cp dtool/dtool /usr/local/bin/dtool` will fail
    without sudo on stock macOS (and `/usr/local/bin` doesn't exist on Apple
    Silicon by default; should use `/opt/homebrew/bin` or `~/.local/bin`).

---

## 3. Target architecture

```
dotfiles/
├── dtool/                        # the only entry point users invoke
│   ├── cmd/dtool/main.go         # tiny entry, flag parsing
│   ├── internal/
│   │   ├── app/                  # root TUI model (was app.go)
│   │   ├── ui/                   # styles, shared components
│   │   ├── runner/               # exec helpers (sudo, streaming, dry-run)
│   │   ├── fs/                   # disk size, scanning, human-readable
│   │   └── pages/
│   │       ├── home/
│   │       ├── cleaner/
│   │       ├── nvim/
│   │       ├── burner/
│   │       └── git/
│   ├── go.mod
│   └── Makefile (or use root makefile)
├── older_scripts/                # original .sh files moved here, untouched
│   ├── clean_system.sh
│   ├── burn-iso.sh
│   ├── dotfiles.sh
│   ├── setup_nvim.sh
│   └── README.md                 # one-line note: "kept until dtool is verified"
├── nvim-config/                  # unchanged
├── README.md
└── makefile                      # build/install targets only
```

Shell scripts are **moved** (via `git mv`, history preserved) into
`older_scripts/` and **never deleted by this plan**. The user removes them
manually after they're satisfied each Go port matches behavior.

---

## 4. Phased plan

### Phase 0 — Baseline (½ day)

- [ ] Add `dtool/.golangci.yml` (gofmt, govet, errcheck, staticcheck, gosec).
- [ ] Add a tiny GitHub Actions workflow: `go build`, `go vet`, `golangci-lint`,
      `go test ./...`.
- [ ] Add a `dtool/README.md` documenting commands, dry-run, and how to
      contribute a new page.
- [ ] Decide install location: `~/.local/bin/dtool` (no sudo) is the safest
      default; update `makefile` accordingly and add it to `PATH` via the
      shell rc (offer, don't force).

### Phase 1 — Fix the shipped Go bugs (1–2 days)

These are blockers for using `dtool` as the only entry point.

- [ ] **`pages/cleaner.go`**: stop relying on shell globs. Replace
      `runner.RunWithSudo("rm", "-rf", dir+"/*")` with an `os.ReadDir` loop
      that calls `runner.RunWithSudo("rm", "-rf", entryPath)` per entry, or
      with a single `sh -c "rm -rf /Library/Caches/*"` invocation that is
      explicit about needing a shell.
- [ ] **`runner/runner.go`**: add `RunInteractive` that wires `os.Stdin /
      Stdout / Stderr` and is used for any command that may prompt
      (`sudo`, `brew`, `dd`). For sudo specifically, do a `sudo -v` priming
      call at the start of any cleaner action that needs root.
- [ ] **`pages/git.go`**: default `m.checked` to all `false`. Mark the
      current branch line read-only/non-selectable (already filtered, but make
      the screen show it clearly).
- [ ] **`pages/cleaner.go`**: restore custom-path entry for scans (input
      step before the scan runs). Mirror the bash version's UX.
- [ ] **`pages/nvim.go`**: install brew packages one at a time with
      per-package status, so partial successes are reported correctly. Skip
      packages already installed (`brew list <pkg>` check).
- [ ] **`pages/burner.go`**: stream `dd` output (use `cmd.StdoutPipe`/
      `StderrPipe` and a `tea.Tick` to push progress lines as `tea.Msg`).
      Fix `.iso` → `.img.dmg` derivation: ask `hdiutil` for its output path
      or pass `-o name` and append `.dmg` deterministically.
- [ ] **`pages/cleaner.go`**: emit a "scanning…" `tea.Msg` and a final
      result so the screen isn't frozen during long walks.

### Phase 2 — Restructure into `internal/` (1 day)

Pure refactor — no behavior change.

- [ ] Move `main.go` → `cmd/dtool/main.go`.
- [ ] Move `app.go`, `styles.go` → `internal/app/` and `internal/ui/`.
- [ ] Move `runner/` → `internal/runner/`.
- [ ] Split `pages/` into one package per page under `internal/pages/<name>/`.
- [ ] Extract `humanReadable`, `dirSizeKB`, `timeAgo`, `walkScan` from
      `cleaner.go` into `internal/fs/`. They're useful in tests and other
      pages.
- [ ] Update `module dtool` path / imports.

### Phase 3 — Add tests (1–2 days)

- [ ] `internal/fs/`: unit tests for `humanReadable`, `dirSizeKB`,
      `timeAgo`, `walkScan` against `t.TempDir()` fixtures.
- [ ] `internal/runner/`: tests for dry-run gating, sudo prefixing.
- [ ] `internal/pages/git/`: parse-branches test against canned `git branch`
      output.
- [ ] Smoke test: `go test -run TestApp ./internal/app/` that boots the TUI
      with `tea.WithoutRenderer()` and walks through Home → each page →
      back, asserting no panic.

### Phase 4 — Park the shell scripts in `older_scripts/` (½ day)

Once `dtool` is tested, the shell scripts step out of the way **but stay in
the repo for fallback**. They are not edited.

- [ ] `mkdir older_scripts/`.
- [ ] `git mv clean_system.sh burn-iso.sh dotfiles.sh setup_nvim.sh older_scripts/`
      so blame/history follows the move; the file contents are unchanged.
- [ ] Add `older_scripts/README.md` with a single line: *"Original shell
      scripts. Kept here as a fallback until `dtool` is verified on this
      machine. Safe to delete once you're happy with the Go port."*
- [ ] Update root `README.md`: replace the three install snippets with a
      single "install dtool" block, plus a small footnote pointing at
      `older_scripts/` for users who still want the bash flow.
- [ ] Update `makefile`: point existing targets at the new locations
      (`bash older_scripts/clean_system.sh`, etc.) so `make clean_system`
      keeps working unchanged. Add a comment that those targets are
      deprecated and will be removed when the user deletes `older_scripts/`.
- [ ] Add a `dtool nvim` shortcut (or `dtool --setup-nvim`) so first-time
      users have a one-command bootstrap that doesn't need the old
      `setup_nvim.sh`.

**Explicit non-goals of this phase:**
- Do **not** modify the contents of any `.sh` file.
- Do **not** delete any `.sh` file. Deletion is a manual step the user
  takes after their own verification.

### Phase 5 — Nice-to-haves (optional, prioritize after dogfooding)

- [ ] **Config file** at `~/.config/dtool/config.toml` for default scan dirs,
      preferred dry-run, etc.
- [ ] **Logging**: write a structured log to `~/.local/state/dtool/log.jsonl`
      so postmortems on "what did it delete" are possible.
- [ ] **Undo**: for cache deletions, move to `~/.Trash` instead of
      `rm -rf` when feasible (use `osascript -e 'tell application "Finder" to delete …'`
      or the `trash` brew package).
- [ ] **Linux support**: gate macOS-only paths (`/Library/Caches`,
      `dscacheutil`, `diskutil`) behind `runtime.GOOS == "darwin"` and add
      Linux equivalents.
- [ ] **Background tasks**: kick long scans off in goroutines that report
      progress via `tea.Cmd`s; show a spinner.
- [ ] **`dtool doctor`**: a subcommand that checks for required tools
      (`brew`, `git`, `nvim`, `hdiutil`, `dd`) and reports what's missing.

---

## 5. Sequencing & estimate

| Phase | Effort | Blocker for? |
|-------|--------|---------------|
| 0 — Baseline (lint/CI/install path) | ½ day | nothing |
| 1 — Bug fixes                       | 1–2 days | making dtool the default |
| 2 — Restructure                     | 1 day | tests |
| 3 — Tests                           | 1–2 days | parking shell |
| 4 — Park shell in `older_scripts/`  | ½ day | — |
| 5 — Nice-to-haves                   | open | — |
| (Manual, by user) Delete `older_scripts/` once verified | — | — |

Total realistic effort to "Go tool is the default and tested, originals
parked as a fallback": **~1 working week**. Final cleanup of `older_scripts/`
happens on the user's timeline, not the plan's.

---

## 6. Open questions

1. Are you okay with `~/.local/bin` as the install destination (no sudo), or do
   you want to keep `/usr/local/bin`?
2. Should `dtool` ever shell out (`bash -c`) for tasks where bash semantics
   are genuinely simpler (glob expansion, pipelines), or do we want it 100%
   pure Go?
3. Do you care about Linux support, or is this strictly macOS forever?
4. Do you want the burner flow at all, or is that one a candidate for
   deletion (it's the riskiest one)?

Answers to these change phases 1, 4, and 5 — but none of them block phase 0 or
2 from starting.
