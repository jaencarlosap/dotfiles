package pages

import (
	"dtool/runner"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type cleanerState int

const (
	cleanerSelect cleanerState = iota
	cleanerScanInput
	cleanerRunning
	cleanerDone
	cleanerScanResults
)

type cleanItem struct {
	label     string
	desc      string
	needsSudo bool
	checked   bool
}

type CleanerModel struct {
	DryRun      bool
	state       cleanerState
	cursor      int
	items       []cleanItem
	logs        []string
	totalFreed  int64
	scanItems   []ScanItem
	scanCursor  int
	scanChecked []bool
	scanLabel   string
	scanTarget  string // "node_modules" or "venv" — picked when entering input
	scanInput   string // editable space-separated paths, defaulted on entry
}

func NewCleanerModel() CleanerModel {
	return CleanerModel{
		items: []cleanItem{
			{label: "User Caches", desc: "~/Library/Caches, CrashReporter, Logs", needsSudo: false},
			{label: "System Caches", desc: "/Library/Caches", needsSudo: true},
			{label: "Temporary Files", desc: "/private/tmp", needsSudo: true},
			{label: "Flush DNS", desc: "Flush DNS resolver cache", needsSudo: true},
			{label: "Node Modules", desc: "Scan and delete node_modules directories", needsSudo: false},
			{label: "Python Venvs", desc: "Scan and delete .venv/venv/env directories", needsSudo: false},
			{label: "Go Cache", desc: "Clean Go module and build caches", needsSudo: false},
		},
	}
}

func (m CleanerModel) Init() tea.Cmd {
	return nil
}

func (m CleanerModel) Update(msg tea.Msg) (CleanerModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch m.state {
		case cleanerSelect:
			return m.updateSelect(msg)
		case cleanerScanInput:
			return m.updateScanInput(msg)
		case cleanerScanResults:
			return m.updateScanResults(msg)
		case cleanerDone:
			// any key goes back to select
			m.state = cleanerSelect
			return m, nil
		}

	case TaskDoneMsg:
		m.logs = append(m.logs, msg.Output)
		if msg.FreedKB > 0 {
			m.totalFreed += msg.FreedKB
		}
		m.state = cleanerDone
		return m, nil

	case SudoCleanDoneMsg:
		m.logs = append(m.logs, msg.Results...)
		m.totalFreed += msg.FreedKB
		if msg.Err != nil {
			m.logs = append(m.logs, fmt.Sprintf("sudo error: %v", msg.Err))
		}
		if len(msg.PendingNonSudo) > 0 {
			return m, runNonSudoTasks(msg.PendingNonSudo, msg.DryRun)
		}
		m.state = cleanerDone
		return m, nil

	case ScanResultMsg:
		m.scanItems = msg.Items
		m.scanChecked = make([]bool, len(msg.Items))
		m.scanCursor = 0
		if len(msg.Items) == 0 {
			m.logs = append(m.logs, "No items found.")
			m.state = cleanerDone
		} else {
			m.state = cleanerScanResults
		}
		return m, nil
	}

	return m, nil
}

func (m CleanerModel) updateSelect(msg tea.KeyMsg) (CleanerModel, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < len(m.items)-1 {
			m.cursor++
		}
	case " ":
		m.items[m.cursor].checked = !m.items[m.cursor].checked
	case "a":
		// toggle all cache items (0-3)
		allChecked := true
		for i := 0; i < 4; i++ {
			if !m.items[i].checked {
				allChecked = false
				break
			}
		}
		for i := 0; i < 4; i++ {
			m.items[i].checked = !allChecked
		}
	case "enter":
		return m.runSelected()
	}
	return m, nil
}

func (m CleanerModel) updateScanInput(msg tea.KeyMsg) (CleanerModel, tea.Cmd) {
	switch msg.String() {
	case "enter":
		dirs := parseScanDirs(m.scanInput)
		if len(dirs) == 0 {
			return m, nil
		}
		m.state = cleanerRunning
		if m.scanTarget == "node_modules" {
			return m, scanInDirs(dirs, "node_modules")
		}
		return m, scanVenvsInDirs(dirs)
	case "esc":
		m.state = cleanerSelect
		return m, nil
	case "backspace":
		if len(m.scanInput) > 0 {
			m.scanInput = m.scanInput[:len(m.scanInput)-1]
		}
	default:
		if len(msg.String()) == 1 {
			m.scanInput += msg.String()
		}
	}
	return m, nil
}

func (m CleanerModel) updateScanResults(msg tea.KeyMsg) (CleanerModel, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.scanCursor > 0 {
			m.scanCursor--
		}
	case "down", "j":
		if m.scanCursor < len(m.scanItems)-1 {
			m.scanCursor++
		}
	case " ":
		m.scanChecked[m.scanCursor] = !m.scanChecked[m.scanCursor]
	case "a":
		allChecked := true
		for _, c := range m.scanChecked {
			if !c {
				allChecked = false
				break
			}
		}
		for i := range m.scanChecked {
			m.scanChecked[i] = !allChecked
		}
	case "enter":
		return m.deleteScanned()
	case "esc":
		m.state = cleanerSelect
		return m, nil
	}
	return m, nil
}

func (m CleanerModel) runSelected() (CleanerModel, tea.Cmd) {
	// Scan items (node_modules / python venvs) route through the input
	// step so the user can override the default scan paths.
	for i, item := range m.items {
		if item.checked && (i == 4 || i == 5) {
			m.items[i].checked = false
			m.scanInput = strings.Join(defaultScanDirs(), " ")
			if i == 4 {
				m.scanLabel = "node_modules"
				m.scanTarget = "node_modules"
			} else {
				m.scanLabel = "Python venvs"
				m.scanTarget = "venv"
			}
			m.state = cleanerScanInput
			return m, nil
		}
	}

	var selected []int
	for i, item := range m.items {
		if item.checked {
			selected = append(selected, i)
		}
	}

	if len(selected) == 0 {
		return m, nil
	}

	m.state = cleanerRunning
	m.logs = nil
	return m, runCleanTasks(selected, m.DryRun)
}

func (m CleanerModel) deleteScanned() (CleanerModel, tea.Cmd) {
	var toDelete []string
	var totalKB int64
	for i, item := range m.scanItems {
		if m.scanChecked[i] {
			toDelete = append(toDelete, item.Path)
			totalKB += item.SizeKB
		}
	}
	if len(toDelete) == 0 {
		m.state = cleanerSelect
		return m, nil
	}
	m.state = cleanerRunning
	dryRun := m.DryRun
	return m, func() tea.Msg {
		var results []string
		for _, path := range toDelete {
			if dryRun {
				results = append(results, fmt.Sprintf("[DRY RUN] Would delete: %s", path))
			} else {
				err := os.RemoveAll(path)
				if err != nil {
					results = append(results, fmt.Sprintf("Error deleting %s: %v", path, err))
				} else {
					results = append(results, fmt.Sprintf("Deleted: %s", path))
				}
			}
		}
		freedKB := totalKB
		if dryRun {
			freedKB = 0
		}
		return TaskDoneMsg{
			Label:   "Scan cleanup",
			Output:  strings.Join(results, "\n"),
			FreedKB: freedKB,
		}
	}
}

func (m CleanerModel) View() string {
	switch m.state {
	case cleanerSelect:
		return m.viewSelect()
	case cleanerScanInput:
		return m.viewScanInput()
	case cleanerRunning:
		return "\n  Running...\n"
	case cleanerDone:
		return m.viewDone()
	case cleanerScanResults:
		return m.viewScanResults()
	}
	return ""
}

func (m CleanerModel) viewScanInput() string {
	prompt := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true)
	muted := lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280"))
	input := lipgloss.NewStyle().Foreground(lipgloss.Color("#E5E7EB"))

	s := "\n"
	s += prompt.Render(fmt.Sprintf("  Scan paths for %s (space-separated):", m.scanLabel)) + "\n\n"
	s += input.Render("  > "+m.scanInput) + "|\n\n"
	s += muted.Render("  enter: scan  esc: cancel") + "\n"
	return s
}

func (m CleanerModel) viewSelect() string {
	s := "\n"
	sectionStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true)
	itemStyle := lipgloss.NewStyle().PaddingLeft(2)
	descItemStyle := lipgloss.NewStyle().PaddingLeft(6).Foreground(lipgloss.Color("#6B7280"))

	s += sectionStyle.Render("  Cache Cleaning") + "\n\n"
	for i := 0; i < 4; i++ {
		s += m.renderCheckItem(i, itemStyle, descItemStyle)
	}

	s += "\n" + sectionStyle.Render("  Developer Cleanup") + "\n\n"
	for i := 4; i < 7; i++ {
		s += m.renderCheckItem(i, itemStyle, descItemStyle)
	}

	s += "\n"
	muted := lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280"))
	s += muted.Render("  a: toggle all caches  space: toggle  enter: run selected") + "\n"

	if m.totalFreed > 0 {
		s += "\n" + lipgloss.NewStyle().Foreground(lipgloss.Color("#22C55E")).Render(
			fmt.Sprintf("  Total freed: %s", humanReadable(m.totalFreed))) + "\n"
	}

	return s
}

func (m CleanerModel) renderCheckItem(i int, itemStyle, descItemStyle lipgloss.Style) string {
	item := m.items[i]
	cursor := "  "
	if m.cursor == i {
		cursor = "> "
	}
	check := "[ ]"
	if item.checked {
		check = "[x]"
	}
	sudo := ""
	if item.needsSudo {
		sudo = lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Render(" [sudo]")
	}
	label := item.label + sudo
	if m.cursor == i {
		label = lipgloss.NewStyle().Foreground(lipgloss.Color("#7C3AED")).Bold(true).Render(label)
	}
	s := itemStyle.Render(fmt.Sprintf("%s%s %s", cursor, check, label)) + "\n"
	s += descItemStyle.Render(item.desc) + "\n"
	return s
}

func (m CleanerModel) viewDone() string {
	s := "\n  Results:\n\n"
	for _, log := range m.logs {
		for _, line := range strings.Split(log, "\n") {
			s += "  " + line + "\n"
		}
	}
	if m.totalFreed > 0 {
		s += fmt.Sprintf("\n  Total freed: %s\n", humanReadable(m.totalFreed))
	}
	s += "\n  Press any key to continue...\n"
	return s
}

func (m CleanerModel) viewScanResults() string {
	s := fmt.Sprintf("\n  Found %d %s:\n\n", len(m.scanItems), m.scanLabel)
	s += fmt.Sprintf("  %-4s %-12s %-20s %s\n", "#", "Size", "Modified", "Path")
	s += "  ---- ------------ -------------------- " + strings.Repeat("-", 40) + "\n"

	for i, item := range m.scanItems {
		cursor := "  "
		if m.scanCursor == i {
			cursor = "> "
		}
		check := "[ ]"
		if m.scanChecked[i] {
			check = "[x]"
		}
		line := fmt.Sprintf("%s%s %-4d %-12s %-20s %s",
			cursor, check, i+1, humanReadable(item.SizeKB), item.ModTime, item.Path)
		if m.scanCursor == i {
			line = lipgloss.NewStyle().Foreground(lipgloss.Color("#7C3AED")).Render(line)
		}
		s += line + "\n"
	}

	s += "\n"
	muted := lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280"))
	s += muted.Render("  space: toggle  a: toggle all  enter: delete selected  esc: back") + "\n"
	return s
}

// --- Commands ---

// indicesNeedSudo returns true if any selected index requires root.
func indicesNeedSudo(indices []int) bool {
	for _, i := range indices {
		if i == 1 || i == 2 || i == 3 {
			return true
		}
	}
	return false
}

// splitIndices partitions selected indices into the sudo set and the
// non-sudo set, preserving order.
func splitIndices(indices []int) (sudo, nonSudo []int) {
	for _, i := range indices {
		switch i {
		case 1, 2, 3:
			sudo = append(sudo, i)
		default:
			nonSudo = append(nonSudo, i)
		}
	}
	return
}

func runCleanTasks(indices []int, dryRun bool) tea.Cmd {
	sudoIdx, nonSudoIdx := splitIndices(indices)
	if len(sudoIdx) == 0 {
		return runNonSudoTasks(nonSudoIdx, dryRun)
	}
	return runSudoPhase(sudoIdx, nonSudoIdx, dryRun)
}

// runSudoPhase emits a single sudo invocation (one password prompt) for all
// root-requiring tasks. tea.ExecProcess pauses the TUI so the user sees the
// prompt; on completion we either kick off non-sudo work or finish.
func runSudoPhase(sudoIdx, nonSudoIdx []int, dryRun bool) tea.Cmd {
	var script strings.Builder
	var results []string
	var freedKB int64

	for _, idx := range sudoIdx {
		switch idx {
		case 1: // /Library/Caches
			dir := "/Library/Caches"
			sizeKB := dirSizeKB(dir)
			if dryRun {
				results = append(results, fmt.Sprintf("[DRY RUN] Would clean: %s (%s)", dir, humanReadable(sizeKB)))
				continue
			}
			fmt.Fprintf(&script, "rm -rf %s/* 2>/dev/null || true\n", runner.ShellQuote(dir))
			results = append(results, fmt.Sprintf("Cleaned: %s (%s)", dir, humanReadable(sizeKB)))
			freedKB += sizeKB

		case 2: // /private/tmp
			dir := "/private/tmp"
			sizeKB := dirSizeKB(dir)
			if dryRun {
				results = append(results, fmt.Sprintf("[DRY RUN] Would clean: %s (%s)", dir, humanReadable(sizeKB)))
				continue
			}
			fmt.Fprintf(&script, "rm -rf %s/* 2>/dev/null || true\n", runner.ShellQuote(dir))
			results = append(results, fmt.Sprintf("Cleaned: %s (%s)", dir, humanReadable(sizeKB)))
			freedKB += sizeKB

		case 3: // DNS flush
			if dryRun {
				results = append(results, "[DRY RUN] Would flush DNS cache")
				continue
			}
			script.WriteString("dscacheutil -flushcache\n")
			script.WriteString("killall -HUP mDNSResponder 2>/dev/null || true\n")
			results = append(results, "DNS cache flushed")
		}
	}

	if dryRun || script.Len() == 0 {
		return func() tea.Msg {
			return SudoCleanDoneMsg{
				Results:        results,
				FreedKB:        0,
				PendingNonSudo: nonSudoIdx,
				DryRun:         dryRun,
			}
		}
	}

	cmd := runner.SudoShellCmd(script.String())
	return tea.ExecProcess(cmd, func(err error) tea.Msg {
		return SudoCleanDoneMsg{
			Results:        results,
			FreedKB:        freedKB,
			PendingNonSudo: nonSudoIdx,
			DryRun:         dryRun,
			Err:            err,
		}
	})
}

func runNonSudoTasks(indices []int, dryRun bool) tea.Cmd {
	return func() tea.Msg {
		var results []string
		var totalFreed int64
		home := os.Getenv("HOME")

		for _, idx := range indices {
			switch idx {
			case 0: // User caches
				dirs := []string{
					filepath.Join(home, "Library", "Caches"),
					filepath.Join(home, "Library", "Application Support", "CrashReporter"),
					filepath.Join(home, "Library", "Logs"),
				}
				for _, dir := range dirs {
					sizeKB := dirSizeKB(dir)
					if sizeKB == 0 {
						continue
					}
					if dryRun {
						results = append(results, fmt.Sprintf("[DRY RUN] Would clean: %s (%s)", dir, humanReadable(sizeKB)))
					} else {
						clearDir(dir)
						results = append(results, fmt.Sprintf("Cleaned: %s (%s)", dir, humanReadable(sizeKB)))
						totalFreed += sizeKB
					}
				}

			case 6: // Go cache
				goModCache := filepath.Join(home, "go", "pkg", "mod")
				goBuildCache := filepath.Join(home, "Library", "Caches", "go-build")
				modKB := dirSizeKB(goModCache)
				buildKB := dirSizeKB(goBuildCache)
				totalKB := modKB + buildKB

				if totalKB == 0 {
					results = append(results, "No Go caches found")
					continue
				}

				if dryRun {
					results = append(results, fmt.Sprintf("[DRY RUN] Would clean Go caches (%s)", humanReadable(totalKB)))
				} else {
					if runner.CommandExists("go") {
						runner.Run("go", "clean", "-modcache")
						runner.Run("go", "clean", "-cache")
					} else {
						os.RemoveAll(goModCache)
						os.RemoveAll(goBuildCache)
					}
					results = append(results, fmt.Sprintf("Cleaned Go caches (%s)", humanReadable(totalKB)))
					totalFreed += totalKB
				}
			}
		}

		return TaskDoneMsg{
			Label:   "Clean",
			Output:  strings.Join(results, "\n"),
			FreedKB: totalFreed,
		}
	}
}

// defaultScanDirs returns the user-home subdirectories that exist and are
// reasonable defaults for a developer-artifact scan.
func defaultScanDirs() []string {
	home := os.Getenv("HOME")
	candidates := []string{
		filepath.Join(home, "Documents"),
		filepath.Join(home, "Projects"),
		filepath.Join(home, "Developer"),
		filepath.Join(home, "Desktop"),
		filepath.Join(home, "Code"),
	}
	var dirs []string
	for _, d := range candidates {
		if _, err := os.Stat(d); err == nil {
			dirs = append(dirs, d)
		}
	}
	return dirs
}

// parseScanDirs splits a space-separated input string into existing
// directories. Non-existent entries are dropped silently.
func parseScanDirs(input string) []string {
	var dirs []string
	for _, raw := range strings.Fields(input) {
		if _, err := os.Stat(raw); err == nil {
			dirs = append(dirs, raw)
		}
	}
	return dirs
}

func scanInDirs(dirs []string, target string) tea.Cmd {
	return func() tea.Msg {
		var items []ScanItem
		for _, base := range dirs {
			walkScan(base, target, 6, &items)
		}
		return ScanResultMsg{Items: items}
	}
}

func scanVenvsInDirs(dirs []string) tea.Cmd {
	return func() tea.Msg {
		var items []ScanItem
		for _, base := range dirs {
			walkScanVenvs(base, 5, &items)
		}
		return ScanResultMsg{Items: items}
	}
}

// --- Helpers ---

func dirSizeKB(path string) int64 {
	var size int64
	filepath.WalkDir(path, func(_ string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if !d.IsDir() {
			info, err := d.Info()
			if err == nil {
				size += info.Size()
			}
		}
		return nil
	})
	return size / 1024
}

func clearDir(path string) {
	entries, err := os.ReadDir(path)
	if err != nil {
		return
	}
	for _, e := range entries {
		os.RemoveAll(filepath.Join(path, e.Name()))
	}
}

func humanReadable(kb int64) string {
	if kb >= 1048576 {
		return fmt.Sprintf("%.2f GB", float64(kb)/1048576)
	}
	if kb >= 1024 {
		return fmt.Sprintf("%.1f MB", float64(kb)/1024)
	}
	return fmt.Sprintf("%d KB", kb)
}

func walkScan(base, target string, maxDepth int, items *[]ScanItem) {
	filepath.WalkDir(base, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		// Check depth
		rel, _ := filepath.Rel(base, path)
		depth := strings.Count(rel, string(filepath.Separator))
		if depth > maxDepth {
			return filepath.SkipDir
		}
		if d.IsDir() && d.Name() == target {
			sizeKB := dirSizeKB(path)
			parentDir := filepath.Dir(path)
			modTime := timeAgo(filepath.Join(parentDir, "package.json"))
			if modTime == "" {
				modTime = timeAgo(path)
			}
			*items = append(*items, ScanItem{
				Path:    path,
				SizeKB:  sizeKB,
				ModTime: modTime,
			})
			return filepath.SkipDir
		}
		return nil
	})
}

func walkScanVenvs(base string, maxDepth int, items *[]ScanItem) {
	targets := map[string]bool{"venv": true, ".venv": true, "env": true}
	filepath.WalkDir(base, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(base, path)
		depth := strings.Count(rel, string(filepath.Separator))
		if depth > maxDepth {
			return filepath.SkipDir
		}
		if d.IsDir() && targets[d.Name()] {
			cfgPath := filepath.Join(path, "pyvenv.cfg")
			if _, err := os.Stat(cfgPath); err == nil {
				sizeKB := dirSizeKB(path)
				modTime := timeAgo(cfgPath)
				*items = append(*items, ScanItem{
					Path:    path,
					SizeKB:  sizeKB,
					ModTime: modTime,
				})
			}
			return filepath.SkipDir
		}
		return nil
	})
}

func timeAgo(path string) string {
	info, err := os.Stat(path)
	if err != nil {
		return "unknown"
	}
	diff := time.Since(info.ModTime())
	switch {
	case diff < time.Hour:
		return fmt.Sprintf("%d min ago", int(diff.Minutes()))
	case diff < 24*time.Hour:
		return fmt.Sprintf("%d hours ago", int(diff.Hours()))
	case diff < 30*24*time.Hour:
		return fmt.Sprintf("%d days ago", int(diff.Hours()/24))
	case diff < 365*24*time.Hour:
		return fmt.Sprintf("%d months ago", int(diff.Hours()/(24*30)))
	default:
		return fmt.Sprintf("%d years ago", int(diff.Hours()/(24*365)))
	}
}
