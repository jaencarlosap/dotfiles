package main

import (
	"dtool/pages"
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type page int

const (
	homePage page = iota
	installerPage
	cleanerPage
	nvimPage
	burnerPage
	gitPage
)

type App struct {
	currentPage page
	dryRun      bool
	width       int
	height      int

	home      pages.HomeModel
	installer pages.InstallerModel
	cleaner   pages.CleanerModel
	nvim      pages.NvimModel
	burner    pages.BurnerModel
	git       pages.GitModel
}

func NewApp() App {
	return App{
		currentPage: homePage,
		home:        pages.NewHomeModel(),
		installer:   pages.NewInstallerModel(),
		cleaner:     pages.NewCleanerModel(),
		nvim:        pages.NewNvimModel(),
		burner:      pages.NewBurnerModel(),
		git:         pages.NewGitModel(),
	}
}

func (a App) Init() tea.Cmd {
	// `dtool --page installer` entra sin pasar por Home: el Init de la pagina
	// (las comprobaciones de estado de los MCP) tiene que dispararse aqui.
	if a.currentPage == installerPage {
		return a.installer.Init()
	}
	return nil
}

func (a App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
		return a, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return a, tea.Quit
		case "esc":
			if a.currentPage != homePage {
				a.currentPage = homePage
				a.installer = pages.NewInstallerModel()
				a.cleaner = pages.NewCleanerModel()
				a.nvim = pages.NewNvimModel()
				a.burner = pages.NewBurnerModel()
				a.git = pages.NewGitModel()
				return a, nil
			}
		case "d":
			if a.currentPage == homePage {
				a.dryRun = !a.dryRun
				return a, nil
			}
		}

	case pages.NavigateMsg:
		switch msg.Target {
		case "installer":
			a.currentPage = installerPage
			a.installer = pages.NewInstallerModel()
			a.installer.SetDryRun(a.dryRun)
			return a, a.installer.Init()
		case "cleaner":
			a.currentPage = cleanerPage
			a.cleaner = pages.NewCleanerModel()
			a.cleaner.DryRun = a.dryRun
			return a, a.cleaner.Init()
		case "nvim":
			a.currentPage = nvimPage
			a.nvim = pages.NewNvimModel()
			return a, a.nvim.Init()
		case "burner":
			a.currentPage = burnerPage
			a.burner = pages.NewBurnerModel()
			return a, a.burner.Init()
		case "git":
			a.currentPage = gitPage
			a.git = pages.NewGitModel()
			return a, a.git.Init()
		}
	}

	// Delegate to current page
	var cmd tea.Cmd
	switch a.currentPage {
	case homePage:
		a.home, cmd = a.home.Update(msg)
	case installerPage:
		a.installer, cmd = a.installer.Update(msg)
	case cleanerPage:
		a.cleaner, cmd = a.cleaner.Update(msg)
	case nvimPage:
		a.nvim, cmd = a.nvim.Update(msg)
	case burnerPage:
		a.burner, cmd = a.burner.Update(msg)
	case gitPage:
		a.git, cmd = a.git.Update(msg)
	}

	return a, cmd
}

func (a App) View() string {
	header := a.renderHeader()
	var body string

	switch a.currentPage {
	case homePage:
		body = a.home.View()
	case installerPage:
		body = a.installer.View()
	case cleanerPage:
		body = a.cleaner.View()
	case nvimPage:
		body = a.nvim.View()
	case burnerPage:
		body = a.burner.View()
	case gitPage:
		body = a.git.View()
	}

	help := a.renderHelp()
	return fmt.Sprintf("%s\n%s\n%s", header, body, help)
}

func (a App) renderHeader() string {
	title := titleStyle.Render("  dtool")
	subtitle := mutedStyle.Render(" — dotfiles manager")
	line := title + subtitle

	if a.dryRun {
		line += "  " + bannerStyle.Render(" DRY RUN ")
	}

	pageName := ""
	switch a.currentPage {
	case cleanerPage:
		pageName = "System Cleaner"
	case nvimPage:
		pageName = "Neovim Setup"
	case burnerPage:
		pageName = "ISO Burner"
	case gitPage:
		pageName = "Git Tools"
	}

	if pageName != "" {
		line += "\n" + mutedStyle.Render("  > ") + subtitleStyle.Render(pageName)
	}

	border := lipgloss.NewStyle().
		BorderStyle(lipgloss.NormalBorder()).
		BorderBottom(true).
		BorderForeground(colorMuted).
		Width(a.width - 2)

	return border.Render(line)
}

func (a App) renderHelp() string {
	var keys string
	switch a.currentPage {
	case homePage:
		keys = "j/k: navigate  enter: select  d: toggle dry-run  q: quit"
	case cleanerPage:
		keys = "j/k: navigate  space: toggle  enter: run  esc: back"
	case nvimPage:
		keys = "enter: run tasks  esc: back"
	case burnerPage:
		keys = "enter: confirm  esc: back"
	case gitPage:
		keys = "enter: run  esc: back"
	}
	return helpStyle.Render("  " + keys)
}
