package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	dryRun := false
	for _, arg := range os.Args[1:] {
		switch arg {
		case "--dry-run":
			dryRun = true
		case "--help", "-h":
			fmt.Println("Usage: dtool [--dry-run] [--help]")
			fmt.Println()
			fmt.Println("  --dry-run   Preview actions without executing them")
			fmt.Println("  --help, -h  Show this help message")
			os.Exit(0)
		}
	}

	app := NewApp()
	app.dryRun = dryRun
	p := tea.NewProgram(app, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
