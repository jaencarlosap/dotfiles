package pages

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	selectedStyle = lipgloss.NewStyle().PaddingLeft(2).Foreground(lipgloss.Color("#7C3AED")).Bold(true)
	normalStyle   = lipgloss.NewStyle().PaddingLeft(2).Foreground(lipgloss.Color("#E5E7EB"))
	descStyle     = lipgloss.NewStyle().PaddingLeft(4).Foreground(lipgloss.Color("#6B7280"))
)

type menuItem struct {
	title       string
	description string
	target      string
}

type HomeModel struct {
	cursor int
	items  []menuItem
}

func NewHomeModel() HomeModel {
	return HomeModel{
		items: []menuItem{
			{
				title:       "System Cleaner",
				description: "Clean caches, temp files, and developer artifacts",
				target:      "cleaner",
			},
			{
				title:       "Neovim Setup",
				description: "Install and configure Neovim environment",
				target:      "nvim",
			},
			{
				title:       "ISO Burner",
				description: "Write ISO images to USB drives",
				target:      "burner",
			},
			{
				title:       "Git Tools",
				description: "Branch cleanup and git utilities",
				target:      "git",
			},
		},
	}
}

func (m HomeModel) Init() tea.Cmd {
	return nil
}

func (m HomeModel) Update(msg tea.Msg) (HomeModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q":
			return m, tea.Quit
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.items)-1 {
				m.cursor++
			}
		case "enter":
			return m, func() tea.Msg {
				return NavigateMsg{Target: m.items[m.cursor].target}
			}
		}
	}
	return m, nil
}

func (m HomeModel) View() string {
	s := "\n"
	for i, item := range m.items {
		cursor := "  "
		var title string
		if m.cursor == i {
			cursor = "> "
			title = selectedStyle.Render(cursor + item.title)
		} else {
			title = normalStyle.Render(cursor + item.title)
		}
		desc := descStyle.Render(item.description)
		s += fmt.Sprintf("%s\n%s\n\n", title, desc)
	}
	return s
}
