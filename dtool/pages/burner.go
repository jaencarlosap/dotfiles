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

type burnerStep int

const (
	burnerInputISO burnerStep = iota
	burnerShowDisks
	burnerInputDisk
	burnerConfirm
	burnerRunning
	burnerDone
)

type BurnerModel struct {
	step       burnerStep
	isoPath    string
	diskID     string
	diskList   string
	input      string
	cursorPos  int
	output     string
	err        string
}

type burnerDoneMsg struct {
	output string
	err    error
}

func NewBurnerModel() BurnerModel {
	return BurnerModel{
		step: burnerInputISO,
	}
}

func (m BurnerModel) Init() tea.Cmd {
	return nil
}

func (m BurnerModel) Update(msg tea.Msg) (BurnerModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch m.step {
		case burnerInputISO:
			return m.handleTextInput(msg, func() (BurnerModel, tea.Cmd) {
				m.isoPath = m.input
				// Validate file exists
				if _, err := os.Stat(m.isoPath); err != nil {
					m.err = fmt.Sprintf("File not found: %s", m.isoPath)
					m.input = ""
					return m, nil
				}
				m.err = ""
				m.input = ""
				m.step = burnerShowDisks
				return m, fetchDiskList()
			})

		case burnerShowDisks:
			if msg.String() == "enter" {
				m.step = burnerInputDisk
			}
			return m, nil

		case burnerInputDisk:
			return m.handleTextInput(msg, func() (BurnerModel, tea.Cmd) {
				m.diskID = m.input
				m.input = ""
				m.step = burnerConfirm
				return m, nil
			})

		case burnerConfirm:
			return m.handleTextInput(msg, func() (BurnerModel, tea.Cmd) {
				if m.input == "YES" {
					m.step = burnerRunning
					return m, m.runBurn()
				}
				m.err = "Aborted — type exactly YES to confirm"
				m.input = ""
				m.step = burnerInputISO
				return m, nil
			})

		case burnerDone:
			return m, nil
		}

	case DiskListMsg:
		if msg.Err != nil {
			m.err = msg.Err.Error()
		} else {
			m.diskList = msg.Output
		}
		return m, nil

	case burnerDoneMsg:
		m.step = burnerDone
		m.output = msg.output
		if msg.err != nil {
			m.err = msg.err.Error()
		}
		return m, nil
	}

	return m, nil
}

func (m BurnerModel) handleTextInput(msg tea.KeyMsg, onEnter func() (BurnerModel, tea.Cmd)) (BurnerModel, tea.Cmd) {
	switch msg.String() {
	case "enter":
		return onEnter()
	case "backspace":
		if len(m.input) > 0 {
			m.input = m.input[:len(m.input)-1]
		}
	default:
		if len(msg.String()) == 1 {
			m.input += msg.String()
		}
	}
	return m, nil
}

func (m BurnerModel) runBurn() tea.Cmd {
	isoPath := m.isoPath
	diskID := m.diskID
	return func() tea.Msg {
		var results []string
		diskPath := "/dev/" + diskID
		rawDiskPath := "/dev/r" + diskID

		// Unmount
		results = append(results, "Unmounting "+diskPath+"...")
		out, err := runner.Run("diskutil", "unmountDisk", diskPath)
		if err != nil {
			return burnerDoneMsg{output: strings.Join(results, "\n"), err: fmt.Errorf("unmount failed: %s", out)}
		}
		results = append(results, "Unmounted.")

		// Convert ISO to IMG. hdiutil appends .dmg to the -o argument, so we
		// pass the base path (no extension) and expect <base>.dmg as output.
		imgBase := strings.TrimSuffix(isoPath, filepath.Ext(isoPath))
		dmgPath := imgBase + ".dmg"
		results = append(results, "Converting ISO to IMG ("+dmgPath+")...")
		out, err = runner.Run("hdiutil", "convert", "-format", "UDRW", "-o", imgBase, isoPath)
		if err != nil {
			return burnerDoneMsg{output: strings.Join(results, "\n"), err: fmt.Errorf("convert failed: %s", out)}
		}
		results = append(results, "Converted.")

		// Write with dd
		results = append(results, "Writing image to "+rawDiskPath+"...")
		out, err = runner.RunWithSudo("dd", "if="+dmgPath, "of="+rawDiskPath, "bs=1m", "conv=sync")
		if err != nil {
			return burnerDoneMsg{output: strings.Join(results, "\n"), err: fmt.Errorf("dd failed: %s", out)}
		}
		results = append(results, "Write complete.")

		// Eject
		results = append(results, "Ejecting...")
		runner.Run("diskutil", "eject", diskPath)
		results = append(results, "Done! You can remove the USB drive.")

		return burnerDoneMsg{output: strings.Join(results, "\n")}
	}
}

func fetchDiskList() tea.Cmd {
	return func() tea.Msg {
		out, err := runner.Run("diskutil", "list")
		return DiskListMsg{Output: out, Err: err}
	}
}

func (m BurnerModel) View() string {
	s := "\n"
	promptStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true)
	inputStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#E5E7EB"))
	errStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444"))

	switch m.step {
	case burnerInputISO:
		s += promptStyle.Render("  Enter path to ISO file:") + "\n\n"
		s += inputStyle.Render("  > "+m.input) + "|\n"
		if m.err != "" {
			s += "\n" + errStyle.Render("  "+m.err) + "\n"
		}

	case burnerShowDisks:
		s += promptStyle.Render("  Available disks:") + "\n\n"
		for _, line := range strings.Split(m.diskList, "\n") {
			s += "  " + line + "\n"
		}
		s += "\n" + lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280")).Render("  Press enter to continue...") + "\n"

	case burnerInputDisk:
		s += promptStyle.Render("  Enter target disk identifier (e.g. disk2):") + "\n\n"
		s += inputStyle.Render("  > "+m.input) + "|\n"

	case burnerConfirm:
		s += lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444")).Bold(true).Render(
			fmt.Sprintf("  WARNING: This will erase /dev/%s!", m.diskID)) + "\n\n"
		s += fmt.Sprintf("  ISO:  %s\n", m.isoPath)
		s += fmt.Sprintf("  Disk: /dev/%s\n\n", m.diskID)
		s += promptStyle.Render("  Type YES to confirm:") + "\n\n"
		s += inputStyle.Render("  > "+m.input) + "|\n"
		if m.err != "" {
			s += "\n" + errStyle.Render("  "+m.err) + "\n"
		}

	case burnerRunning:
		s += lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Render("  Writing image... this may take a while.") + "\n"

	case burnerDone:
		if m.err != "" {
			s += errStyle.Render("  Error: "+m.err) + "\n\n"
		}
		for _, line := range strings.Split(m.output, "\n") {
			s += "  " + line + "\n"
		}
	}

	return s
}
