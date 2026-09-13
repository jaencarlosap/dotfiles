package pages

import (
	"dtool/runner"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type nvimState int

const (
	nvimReady nvimState = iota
	nvimRunning
	nvimDone
)

// Same list as older_scripts/setup_nvim.sh. `node` is for Copilot and for the
// tree-sitter CLI, which comes from npm: brew's `tree-sitter` is only the
// library, and `tree-sitter-cli` has no bottle on an Intel-prefix Homebrew
// (it builds rust from source).
var nvimBrewPackages = []string{"ripgrep", "fd", "lazygit", "fzf", "node"}

// Neovim itself is not a brew formula here: on an Apple Silicon Mac whose
// Homebrew lives in /usr/local (Intel/Rosetta) there are no bottles anymore and
// neovim's deps fail to compile, and a `brew upgrade tree-sitter` broke the
// existing binary (dyld: libtree-sitter.0.26.dylib not loaded). The check RUNS
// nvim; if it fails, the official arm64 release goes into ~/.local/nvim.
const nvimReleaseURL = "https://github.com/neovim/neovim/releases/download/stable/nvim-macos-arm64.tar.gz"

const nvimNerdFontCask = "font-hack-nerd-font"

type nvimTask struct {
	label  string
	status string // "pending", "running", "done", "failed", "skipped"
	output string
}

type NvimModel struct {
	state   nvimState
	tasks   []nvimTask
	current int
}

type nvimTaskDoneMsg struct {
	index  int
	status string
	output string
}

func NewNvimModel() NvimModel {
	return NvimModel{
		tasks: []nvimTask{
			{label: "Xcode Command Line Tools", status: "pending"},
			{label: "Homebrew", status: "pending"},
			{label: "Neovim", status: "pending"},
			{label: "Install packages (" + strings.Join(nvimBrewPackages, ", ") + ")", status: "pending"},
			{label: "Install tree-sitter CLI (npm)", status: "pending"},
			{label: "Install Nerd Font (" + nvimNerdFontCask + ")", status: "pending"},
			{label: "Symlink Neovim config", status: "pending"},
			{label: "Restore Lazy plugins (lazy-lock.json)", status: "pending"},
		},
	}
}

func (m NvimModel) Init() tea.Cmd {
	return nil
}

func (m NvimModel) Update(msg tea.Msg) (NvimModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "enter":
			if m.state == nvimReady {
				m.state = nvimRunning
				m.current = 0
				m.tasks[0].status = "running"
				return m, m.runTask(0)
			}
		}

	case nvimTaskDoneMsg:
		m.tasks[msg.index].status = msg.status
		m.tasks[msg.index].output = msg.output

		next := msg.index + 1
		if next < len(m.tasks) {
			m.current = next
			m.tasks[next].status = "running"
			return m, m.runTask(next)
		}
		m.state = nvimDone
		return m, nil
	}

	return m, nil
}

func (m NvimModel) runTask(index int) tea.Cmd {
	return func() tea.Msg {
		home := os.Getenv("HOME")
		cwd, _ := os.Getwd()

		switch index {
		case 0: // Xcode Command Line Tools (git + C compiler for treesitter)
			if out, err := runner.Run("xcode-select", "-p"); err == nil {
				return nvimTaskDoneMsg{index: index, status: "skipped", output: "Installed at " + out}
			}
			runner.RunSilent("xcode-select", "--install")
			return nvimTaskDoneMsg{index: index, status: "failed", output: "Not installed: finish the Apple installer dialog, then run this again"}

		case 1: // Homebrew — the install script is interactive (sudo), so it is
			// not run from inside the TUI; point the user at it instead.
			if runner.CommandExists("brew") {
				out, _ := runner.Run("brew", "--version")
				return nvimTaskDoneMsg{index: index, status: "skipped", output: strings.SplitN(out, "\n", 2)[0]}
			}
			return nvimTaskDoneMsg{index: index, status: "failed", output: "Not installed: run `make install_nvim` in a terminal (it installs Homebrew), then come back"}

		case 2: // Neovim: a binary that starts, whatever installed it
			if out, err := runner.Run("nvim", "--version"); err == nil {
				return nvimTaskDoneMsg{index: index, status: "skipped", output: strings.SplitN(out, "\n", 2)[0]}
			}
			prefix, _ := runner.Run("brew", "--prefix")
			if runtime.GOARCH == "arm64" && prefix == "/opt/homebrew" {
				if out, err := runner.Run("brew", "install", "neovim"); err != nil {
					return nvimTaskDoneMsg{index: index, status: "failed", output: strings.SplitN(out, "\n", 2)[0]}
				}
				return nvimTaskDoneMsg{index: index, status: "done", output: "Installed with brew"}
			}
			if runtime.GOARCH != "arm64" {
				return nvimTaskDoneMsg{index: index, status: "failed", output: "No bottle for this Homebrew and no arm64 release to fall back to: install Neovim manually"}
			}
			localDir := filepath.Join(home, ".local", "nvim")
			binDir := filepath.Join(home, ".local", "bin")
			script := "set -e; tmp=$(mktemp -d); curl -fsSL " + runner.ShellQuote(nvimReleaseURL) + " | tar xz -C \"$tmp\"" +
				"; rm -rf " + runner.ShellQuote(localDir) + "; mv \"$tmp/nvim-macos-arm64\" " + runner.ShellQuote(localDir) +
				"; rm -rf \"$tmp\"; mkdir -p " + runner.ShellQuote(binDir) +
				"; ln -sfn " + runner.ShellQuote(filepath.Join(localDir, "bin", "nvim")) + " " + runner.ShellQuote(filepath.Join(binDir, "nvim"))
			if out, err := runner.ShellCmd(script).CombinedOutput(); err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: strings.SplitN(strings.TrimSpace(string(out)), "\n", 2)[0]}
			}
			ver, _ := runner.Run(filepath.Join(localDir, "bin", "nvim"), "--version")
			return nvimTaskDoneMsg{index: index, status: "done", output: strings.SplitN(ver, "\n", 2)[0] + " in " + localDir + " (make sure ~/.local/bin is first in PATH)"}

		case 3: // brew packages, only the missing ones
			listed, _ := runner.Run("brew", "list", "--formula", "-1")
			have := map[string]bool{}
			for _, l := range strings.Split(listed, "\n") {
				have[strings.TrimSpace(l)] = true
			}
			var installed, skipped, failed []string
			for _, pkg := range nvimBrewPackages {
				if have[pkg] {
					skipped = append(skipped, pkg)
					continue
				}
				if out, err := runner.Run("brew", "install", pkg); err != nil {
					failed = append(failed, fmt.Sprintf("%s (%s)", pkg, strings.SplitN(out, "\n", 2)[0]))
				} else {
					installed = append(installed, pkg)
				}
			}
			var summary []string
			if len(installed) > 0 {
				summary = append(summary, "Installed: "+strings.Join(installed, ", "))
			}
			if len(skipped) > 0 {
				summary = append(summary, "Already installed: "+strings.Join(skipped, ", "))
			}
			if len(failed) > 0 {
				summary = append(summary, "Failed: "+strings.Join(failed, ", "))
				return nvimTaskDoneMsg{index: index, status: "failed", output: strings.Join(summary, "\n")}
			}
			status := "done"
			if len(installed) == 0 {
				status = "skipped"
			}
			return nvimTaskDoneMsg{index: index, status: status, output: strings.Join(summary, "\n")}

		case 4: // tree-sitter CLI, prebuilt binary from npm
			if runner.CommandExists("tree-sitter") {
				out, _ := runner.Run("tree-sitter", "--version")
				return nvimTaskDoneMsg{index: index, status: "skipped", output: out}
			}
			if out, err := runner.Run("npm", "install", "-g", "tree-sitter-cli"); err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: strings.SplitN(out, "\n", 2)[0]}
			}
			return nvimTaskDoneMsg{index: index, status: "done", output: "Installed"}

		case 5: // Nerd Font
			listed, _ := runner.Run("brew", "list", "--cask", "-1")
			for _, l := range strings.Split(listed, "\n") {
				if strings.TrimSpace(l) == nvimNerdFontCask {
					return nvimTaskDoneMsg{index: index, status: "skipped", output: "Already installed"}
				}
			}
			if out, err := runner.Run("brew", "install", "--cask", nvimNerdFontCask); err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: strings.SplitN(out, "\n", 2)[0]}
			}
			return nvimTaskDoneMsg{index: index, status: "done", output: "Installed — select 'Hack Nerd Font' in your terminal profile"}

		case 6: // Symlink, backing up any real config instead of deleting it
			nvimConfigRepo := filepath.Join(cwd, "nvim-config")
			localNvimDir := filepath.Join(home, ".config", "nvim")
			if _, err := os.Stat(nvimConfigRepo); err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: "nvim-config/ not found: run dtool from the dotfiles repo root"}
			}
			if target, err := os.Readlink(localNvimDir); err == nil {
				if target == nvimConfigRepo {
					return nvimTaskDoneMsg{index: index, status: "skipped", output: "Already linked"}
				}
				os.Remove(localNvimDir) // a link elsewhere: just replace it
			} else if _, err := os.Lstat(localNvimDir); err == nil {
				backup := localNvimDir + ".bak-" + time.Now().Format("20060102-150405")
				if err := os.Rename(localNvimDir, backup); err != nil {
					return nvimTaskDoneMsg{index: index, status: "failed", output: err.Error()}
				}
			}
			os.MkdirAll(filepath.Dir(localNvimDir), 0755)
			if err := os.Symlink(nvimConfigRepo, localNvimDir); err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: err.Error()}
			}
			return nvimTaskDoneMsg{index: index, status: "done", output: fmt.Sprintf("Linked %s -> %s", localNvimDir, nvimConfigRepo)}

		case 7: // Lazy restore: the versions pinned in lazy-lock.json, not "latest"
			out, err := runner.Run("nvim", "--headless", "+Lazy! restore", "+qa")
			if err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: out}
			}
			return nvimTaskDoneMsg{index: index, status: "done", output: "Plugins restored"}
		}

		return nvimTaskDoneMsg{index: index, status: "failed", output: "Unknown task"}
	}
}

func (m NvimModel) View() string {
	s := "\n"

	statusIcons := map[string]string{
		"pending": lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280")).Render("[     ]"),
		"running": lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Render("[ ... ]"),
		"done":    lipgloss.NewStyle().Foreground(lipgloss.Color("#22C55E")).Render("[  ok ]"),
		"failed":  lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444")).Render("[ err ]"),
		"skipped": lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Render("[ skip]"),
	}

	for _, task := range m.tasks {
		icon := statusIcons[task.status]
		label := task.label
		if task.status == "running" {
			label = lipgloss.NewStyle().Bold(true).Render(label)
		}
		s += fmt.Sprintf("  %s  %s\n", icon, label)
		if task.output != "" && (task.status == "failed" || task.status == "skipped") {
			outputStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280")).PaddingLeft(11)
			// Only show first line of output to keep it clean
			firstLine := strings.Split(task.output, "\n")[0]
			s += outputStyle.Render(firstLine) + "\n"
		}
	}

	s += "\n"
	switch m.state {
	case nvimReady:
		s += lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280")).Render("  Press enter to start setup...") + "\n"
	case nvimRunning:
		s += lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Render("  Running...") + "\n"
	case nvimDone:
		allOk := true
		for _, t := range m.tasks {
			if t.status == "failed" {
				allOk = false
				break
			}
		}
		if allOk {
			s += lipgloss.NewStyle().Foreground(lipgloss.Color("#22C55E")).Render("  Setup complete!") + "\n"
		} else {
			s += lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444")).Render("  Setup finished with errors.") + "\n"
		}
	}

	return s
}
