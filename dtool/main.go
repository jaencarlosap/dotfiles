package main

import (
	"fmt"
	"os"

	"dtool/pages"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	dryRun := false
	startPage := ""
	for i, arg := range os.Args[1:] {
		switch arg {
		case "--dry-run":
			dryRun = true
		case "--page":
			if i+2 <= len(os.Args)-1 {
				startPage = os.Args[i+2]
			}
		case "--help", "-h":
			fmt.Println("Usage: dtool [--dry-run] [--page installer|cleaner|nvim|burner|git] [--help]")
			fmt.Println()
			fmt.Println("  --dry-run   Preview actions without executing them")
			fmt.Println("  --page      Open a page directly (make setup opens the installer)")
			fmt.Println("  --help, -h  Show this help message")
			os.Exit(0)
		}
	}

	app := NewApp()
	app.dryRun = dryRun
	var model tea.Model = app
	if startPage != "" {
		model, _ = app.Update(pages.NavigateMsg{Target: startPage})
	}
	p := tea.NewProgram(model, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
