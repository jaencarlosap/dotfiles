package pages

import (
	"dtool/runner"
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type gitState int

const (
	gitLoading gitState = iota
	gitReady
	gitConfirm
	gitRunning
	gitDone
)

type GitModel struct {
	state    gitState
	current  string
	branches []string
	cursor   int
	checked  []bool
	output   string
	err      string
}

type gitDeleteDoneMsg struct {
	output string
	err    error
}

func NewGitModel() GitModel {
	return GitModel{
		state: gitLoading,
	}
}

func (m GitModel) Init() tea.Cmd {
	return fetchBranches()
}

func fetchBranches() tea.Cmd {
	return func() tea.Msg {
		current, err := runner.Run("git", "branch", "--show-current")
		if err != nil {
			return BranchListMsg{Err: fmt.Errorf("not a git repository")}
		}

		out, err := runner.Run("git", "branch")
		if err != nil {
			return BranchListMsg{Err: err}
		}

		var branches []string
		for _, line := range strings.Split(out, "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			// Skip current branch marker
			line = strings.TrimPrefix(line, "* ")
			if line != current {
				branches = append(branches, line)
			}
		}

		return BranchListMsg{Current: current, Branches: branches}
	}
}

func (m GitModel) Update(msg tea.Msg) (GitModel, tea.Cmd) {
	switch msg := msg.(type) {
	case BranchListMsg:
		if msg.Err != nil {
			m.err = msg.Err.Error()
			m.state = gitDone
			return m, nil
		}
		m.current = msg.Current
		m.branches = msg.Branches
		m.checked = make([]bool, len(msg.Branches))
		m.state = gitReady
		return m, nil

	case tea.KeyMsg:
		switch m.state {
		case gitReady:
			return m.updateReady(msg)
		case gitDone:
			return m, nil
		}

	case gitDeleteDoneMsg:
		m.state = gitDone
		m.output = msg.output
		if msg.err != nil {
			m.err = msg.err.Error()
		}
		return m, nil
	}

	return m, nil
}

func (m GitModel) updateReady(msg tea.KeyMsg) (GitModel, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < len(m.branches)-1 {
			m.cursor++
		}
	case " ":
		if len(m.checked) > 0 {
			m.checked[m.cursor] = !m.checked[m.cursor]
		}
	case "a":
		allChecked := true
		for _, c := range m.checked {
			if !c {
				allChecked = false
				break
			}
		}
		for i := range m.checked {
			m.checked[i] = !allChecked
		}
	case "enter":
		var toDelete []string
		for i, b := range m.branches {
			if m.checked[i] {
				toDelete = append(toDelete, b)
			}
		}
		if len(toDelete) == 0 {
			return m, nil
		}
		m.state = gitRunning
		return m, deleteBranches(toDelete)
	}
	return m, nil
}

func deleteBranches(branches []string) tea.Cmd {
	return func() tea.Msg {
		var results []string
		for _, branch := range branches {
			out, err := runner.Run("git", "branch", "-D", branch)
			if err != nil {
				results = append(results, fmt.Sprintf("Failed to delete %s: %s", branch, out))
			} else {
				results = append(results, fmt.Sprintf("Deleted: %s", branch))
			}
		}
		return gitDeleteDoneMsg{output: strings.Join(results, "\n")}
	}
}

func (m GitModel) View() string {
	s := "\n"

	switch m.state {
	case gitLoading:
		s += lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Render("  Loading branches...") + "\n"

	case gitReady:
		currentStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#22C55E")).Bold(true)
		s += fmt.Sprintf("  Current branch: %s\n\n", currentStyle.Render(m.current))

		if len(m.branches) == 0 {
			s += lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280")).Render("  No other branches found.") + "\n"
			return s
		}

		s += lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true).Render("  Select branches to delete:") + "\n\n"

		for i, branch := range m.branches {
			cursor := "  "
			if m.cursor == i {
				cursor = "> "
			}
			check := "[ ]"
			if m.checked[i] {
				check = "[x]"
			}
			line := fmt.Sprintf("  %s%s %s", cursor, check, branch)
			if m.cursor == i {
				line = lipgloss.NewStyle().Foreground(lipgloss.Color("#7C3AED")).Bold(true).Render(line)
			}
			s += line + "\n"
		}

		s += "\n"
		muted := lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280"))
		s += muted.Render("  space: toggle  a: toggle all  enter: delete selected") + "\n"

	case gitRunning:
		s += lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Render("  Deleting branches...") + "\n"

	case gitDone:
		if m.err != "" {
			s += lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444")).Render("  Error: "+m.err) + "\n\n"
		}
		if m.output != "" {
			for _, line := range strings.Split(m.output, "\n") {
				s += "  " + line + "\n"
			}
		}
	}

	return s
}
