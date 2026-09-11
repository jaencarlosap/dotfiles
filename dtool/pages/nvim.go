package pages

import (
	"dtool/runner"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type nvimState int

const (
	nvimReady nvimState = iota
	nvimRunning
	nvimDone
)

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
			{label: "Symlink Neovim config", status: "pending"},
			{label: "Update Homebrew", status: "pending"},
			{label: "Install packages (neovim, ripgrep, fd, lazygit, fzf)", status: "pending"},
			{label: "Install packer.nvim", status: "pending"},
			{label: "Sync Lazy plugins", status: "pending"},
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
		case 0: // Symlink
			nvimConfigRepo := filepath.Join(cwd, "nvim-config")
			localNvimDir := filepath.Join(home, ".config", "nvim")

			// Check if already linked
			if target, err := os.Readlink(localNvimDir); err == nil && target == nvimConfigRepo {
				return nvimTaskDoneMsg{index: index, status: "skipped", output: "Already linked"}
			}

			os.RemoveAll(localNvimDir)
			os.MkdirAll(filepath.Dir(localNvimDir), 0755)
			err := os.Symlink(nvimConfigRepo, localNvimDir)
			if err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: err.Error()}
			}
			return nvimTaskDoneMsg{index: index, status: "done", output: fmt.Sprintf("Linked %s -> %s", localNvimDir, nvimConfigRepo)}

		case 1: // brew update
			out, err := runner.Run("brew", "update")
			if err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: out}
			}
			return nvimTaskDoneMsg{index: index, status: "done", output: "Homebrew updated"}

		case 2: // brew install packages
			packages := []string{"neovim", "ripgrep", "fd", "lazygit", "fzf"}
			var installed, skipped, failed []string
			for _, pkg := range packages {
				if err := runner.RunSilent("brew", "list", pkg); err == nil {
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

		case 3: // packer.nvim
			packerDir := filepath.Join(home, ".local", "share", "nvim", "site", "pack", "packer", "start", "packer.nvim")
			if _, err := os.Stat(packerDir); err == nil {
				return nvimTaskDoneMsg{index: index, status: "skipped", output: "Already installed"}
			}
			out, err := runner.Run("git", "clone", "--depth", "1", "https://github.com/wbthomason/packer.nvim", packerDir)
			if err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: out}
			}
			return nvimTaskDoneMsg{index: index, status: "done", output: "Cloned packer.nvim"}

		case 4: // Lazy sync
			out, err := runner.Run("nvim", "--headless", "+Lazy! sync", "+qa")
			if err != nil {
				return nvimTaskDoneMsg{index: index, status: "failed", output: out}
			}
			return nvimTaskDoneMsg{index: index, status: "done", output: "Plugins synced"}
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
