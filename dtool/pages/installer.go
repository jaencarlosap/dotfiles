package pages

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"dtool/runner"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Installer: elige que instalar o ejecutar de lo que hay en el repo y corre
// los pasos EN ORDEN, cada uno como proceso visible (tea.ExecProcess), asi
// que los que preguntan —sudo, `gh auth login`, `mcporter auth` con su
// navegador— se ven y se contestan como en una terminal normal.
//
// Los servidores MCP salen del catalogo versionado (opencode-config/mcporter/
// mcporter.json) con su estado real (sondeado con --no-oauth: mirar no
// autentica). Marcas solo los que quieres: cada auth abre el navegador y no
// todos hacen falta en cada PC.

type installerState int

const (
	installerSelect installerState = iota
	installerConfirm
	installerRunning
	installerDone
)

type installStep struct {
	title    string
	desc     string
	cmd      string // se ejecuta con sh -c desde la raiz del repo
	group    string // "setup" | "auth" | "maintenance"
	selected bool
	status   string // "", "running", "done", "failed", "skipped"
	note     string
	mcp      string // nombre del servidor MCP si el paso es un auth
}

type InstallerModel struct {
	state    installerState
	cursor   int
	steps    []installStep
	queue    []int
	repo     string
	repoErr  string
	dryRun   bool
	mcpState map[string]string // server -> "ok (N tools)" | "pending" | "checking"
	width    int
}

type installStepDoneMsg struct {
	index int
	err   error
}

type mcpStatusMsg struct {
	server string
	status string
}

var (
	instGroupStyle = lipgloss.NewStyle().PaddingLeft(2).Foreground(lipgloss.Color("#A78BFA")).Bold(true)
	instOKStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("#34D399"))
	instWarnStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#FBBF24"))
	instFailStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#F87171"))
)

func NewInstallerModel() InstallerModel {
	m := InstallerModel{mcpState: map[string]string{}}
	m.repo, m.repoErr = findRepoRoot()
	m.steps = []installStep{
		{group: "setup", title: "opencode config", desc: "symlinks ~/.config/opencode + gh (make install_opencode)", cmd: "make install_opencode"},
		{group: "setup", title: "mcporter (MCP por bash)", desc: "instala mcporter y enlaza el catalogo de servidores; no autentica nada (make install_mcporter)", cmd: "make install_mcporter"},
		{group: "setup", title: "herdr", desc: "runtime persistente para agentes: binario, config, integraciones (make install_herdr)", cmd: "make install_herdr"},
		{group: "setup", title: "Neovim", desc: "Xcode CLT / Homebrew / neovim + nvim-config (make install_nvim YES=1)", cmd: "make install_nvim YES=1"},
		{group: "auth", title: "GitHub: gh auth login", desc: "una vez por maquina; abre el navegador", cmd: "gh auth login"},
	}
	for _, s := range m.mcpServers() {
		m.steps = append(m.steps, installStep{
			group: "auth", mcp: s,
			title: "MCP auth: " + s,
			desc:  "mcporter auth " + s + " (abre el navegador; el token queda en ~/.mcporter)",
			cmd:   "mcporter auth " + s,
		})
		m.mcpState[s] = "checking"
	}
	m.steps = append(m.steps,
		installStep{group: "maintenance", title: "Limpieza de disco", desc: "caches de usuario, Go, npm/brew/cargo, Docker sin volumenes (make clean_disk)", cmd: "make clean_disk"},
		installStep{group: "maintenance", title: "Limpieza de disco (sudo)", desc: "caches de sistema y /private/tmp; pide contraseña (make clean_disk_sudo)", cmd: "make clean_disk_sudo"},
	)
	return m
}

// findRepoRoot: dtool se lanza desde la raiz del repo (make setup) o desde
// cualquier subdirectorio; se sube hasta encontrar opencode-config/Makefile.
func findRepoRoot() (string, string) {
	if env := os.Getenv("DOTFILES"); env != "" {
		return env, ""
	}
	dir, err := os.Getwd()
	if err != nil {
		return "", err.Error()
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "opencode-config", "Makefile")); err == nil {
			return dir, ""
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", "no encuentro la raiz del repo (opencode-config/Makefile): lanza dtool desde dotfiles/ o exporta DOTFILES"
		}
		dir = parent
	}
}

// mcpServers lee el catalogo del repo (existe antes de instalar nada).
func (m InstallerModel) mcpServers() []string {
	if m.repo == "" {
		return nil
	}
	raw, err := os.ReadFile(filepath.Join(m.repo, "opencode-config", "mcporter", "mcporter.json"))
	if err != nil {
		return nil
	}
	var cfg struct {
		Servers map[string]json.RawMessage `json:"mcpServers"`
	}
	if json.Unmarshal(raw, &cfg) != nil {
		return nil
	}
	names := make([]string, 0, len(cfg.Servers))
	for k := range cfg.Servers {
		names = append(names, k)
	}
	sort.Strings(names)
	return names
}

// SetDryRun: con --dry-run los pasos solo se listan, no se ejecutan.
func (m *InstallerModel) SetDryRun(v bool) { m.dryRun = v }

func (m InstallerModel) Init() tea.Cmd {
	var cmds []tea.Cmd
	for _, s := range m.steps {
		if s.mcp != "" {
			cmds = append(cmds, checkMCP(s.mcp))
		}
	}
	return tea.Batch(cmds...)
}

// checkMCP pregunta a mcporter si el servidor ya esta autenticado. Es la
// misma comprobacion de `make mcp-status`, en paralelo y sin bloquear la TUI.
func checkMCP(server string) tea.Cmd {
	return func() tea.Msg {
		if _, err := exec.LookPath("mcporter"); err != nil {
			return mcpStatusMsg{server: server, status: "mcporter no instalado (marca antes 'mcporter (MCP por bash)')"}
		}
		// --no-oauth: sin el, en una maquina sin token esta sonda ABRIA EL
		// NAVEGADOR para cada servidor al entrar en la pagina (visto el 2026-09-21).
		out, _ := runner.Run("mcporter", "list", server, "--status", "--no-oauth")
		for _, line := range strings.Split(out, "\n") {
			if i := strings.Index(line, " tools"); i > 0 {
				start := strings.LastIndex(line[:i], "(")
				if start >= 0 {
					return mcpStatusMsg{server: server, status: "ok (" + line[start+1:i] + " tools)"}
				}
				return mcpStatusMsg{server: server, status: "ok"}
			}
		}
		return mcpStatusMsg{server: server, status: "pending"}
	}
}

func (m InstallerModel) Update(msg tea.Msg) (InstallerModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
	case mcpStatusMsg:
		m.mcpState[msg.server] = msg.status
	case installStepDoneMsg:
		if msg.err != nil {
			m.steps[msg.index].status = "failed"
			m.steps[msg.index].note = msg.err.Error()
		} else {
			m.steps[msg.index].status = "done"
		}
		return m.runNext()
	case tea.KeyMsg:
		switch m.state {
		case installerSelect:
			return m.updateSelect(msg)
		case installerConfirm:
			switch msg.String() {
			case "y", "Y", "enter":
				m.state = installerRunning
				return m.runNext()
			case "n", "N", "esc", "q":
				m.state = installerSelect
				m.queue = nil
			}
			return m, nil
		case installerDone:
			switch msg.String() {
			case "enter", "r":
				fresh := NewInstallerModel()
				fresh.dryRun = m.dryRun
				return fresh, fresh.Init()
			}
		}
	}
	return m, nil
}

func (m InstallerModel) updateSelect(msg tea.KeyMsg) (InstallerModel, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < len(m.steps)-1 {
			m.cursor++
		}
	case " ", "x":
		m.steps[m.cursor].selected = !m.steps[m.cursor].selected
	case "a":
		all := true
		for _, s := range m.steps {
			if !s.selected {
				all = false
				break
			}
		}
		for i := range m.steps {
			m.steps[i].selected = !all
		}
	case "p":
		// solo lo pendiente: setup + auths sin token
		for i := range m.steps {
			s := &m.steps[i]
			switch {
			case s.group == "setup":
				s.selected = true
			case s.mcp != "":
				s.selected = m.mcpState[s.mcp] == "pending"
			case s.cmd == "gh auth login":
				_, err := runner.Run("gh", "auth", "status")
				s.selected = err != nil
			default:
				s.selected = false
			}
		}
	case "enter":
		if m.repo == "" {
			return m, nil
		}
		m.queue = m.queue[:0]
		for i, s := range m.steps {
			if s.selected {
				m.queue = append(m.queue, i)
				m.steps[i].status = ""
				m.steps[i].note = ""
			}
		}
		if len(m.queue) == 0 {
			return m, nil
		}
		// Nunca se ejecuta directo desde la lista: primero se ve que va a
		// correr y en que orden. Una tecla de mas (o `a` = todo) no dispara nada.
		m.state = installerConfirm
	}
	return m, nil
}

// runNext saca el siguiente paso de la cola y lo ejecuta como proceso
// visible. Un fallo no para la cola: se anota y sigue, y al final se ve todo.
func (m InstallerModel) runNext() (InstallerModel, tea.Cmd) {
	if len(m.queue) == 0 {
		m.state = installerDone
		return m, nil
	}
	idx := m.queue[0]
	m.queue = m.queue[1:]
	step := &m.steps[idx]
	step.status = "running"
	if m.dryRun {
		step.status = "skipped"
		step.note = "[dry-run] " + step.cmd
		return m.runNext()
	}
	script := fmt.Sprintf("cd %s && echo && echo '▶ %s' && echo && %s; rc=$?; echo; if [ $rc -eq 0 ]; then echo '✅ %s'; else echo \"❌ %s (exit $rc)\"; fi; echo 'Enter para continuar...'; read _ </dev/tty; exit $rc",
		runner.ShellQuote(m.repo), step.title, step.cmd, step.title, step.title)
	cmd := runner.ShellCmd(script)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return m, tea.ExecProcess(cmd, func(err error) tea.Msg {
		return installStepDoneMsg{index: idx, err: err}
	})
}

func (m InstallerModel) View() string {
	var b strings.Builder
	if m.repoErr != "" {
		b.WriteString(instFailStyle.Render("  " + m.repoErr))
		b.WriteString("\n")
		return b.String()
	}
	b.WriteString(descStyle.Render("Repo: " + m.repo))
	b.WriteString("\n\n")
	lastGroup := ""
	for i, s := range m.steps {
		if s.group != lastGroup {
			lastGroup = s.group
			label := map[string]string{"setup": "Instalar", "auth": "Autenticar (abre el navegador)", "maintenance": "Mantenimiento"}[s.group]
			b.WriteString(instGroupStyle.Render(label))
			b.WriteString("\n")
		}
		box := "[ ]"
		if s.selected {
			box = "[x]"
		}
		state := ""
		switch s.status {
		case "running":
			state = instWarnStyle.Render("  ⏳")
		case "done":
			state = instOKStyle.Render("  ✅")
		case "failed":
			state = instFailStyle.Render("  ❌ " + firstLine(s.note))
		case "skipped":
			state = descStyle.Render(firstLine(s.note))
		}
		if s.mcp != "" {
			switch st := m.mcpState[s.mcp]; {
			case strings.HasPrefix(st, "ok"):
				state += instOKStyle.Render("  ya autenticado " + strings.TrimPrefix(st, "ok "))
			case st == "pending":
				state += instWarnStyle.Render("  sin autenticar")
			case st == "checking":
				state += descStyle.Render("  comprobando...")
			default:
				state += instFailStyle.Render("  " + st)
			}
		}
		line := fmt.Sprintf("%s %s%s", box, s.title, state)
		if i == m.cursor && m.state == installerSelect {
			b.WriteString(selectedStyle.Render("› " + line))
		} else {
			b.WriteString(normalStyle.Render("  " + line))
		}
		b.WriteString("\n")
		b.WriteString(descStyle.Render(s.desc))
		b.WriteString("\n")
	}
	b.WriteString("\n")
	switch m.state {
	case installerConfirm:
		b.WriteString(instGroupStyle.Render("Se va a ejecutar, en este orden:"))
		b.WriteString("\n")
		for n, idx := range m.queue {
			b.WriteString(normalStyle.Render(fmt.Sprintf("  %d. %s   %s", n+1, m.steps[idx].title, descStyle.Render(m.steps[idx].cmd))))
			b.WriteString("\n")
		}
		b.WriteString("\n")
		b.WriteString(instWarnStyle.Render("  y/enter ejecutar · n volver a la lista"))
	case installerSelect:
		b.WriteString(descStyle.Render("space/x marcar · a todo/nada · p solo lo pendiente · enter revisar y confirmar · esc volver"))
	case installerRunning:
		b.WriteString(instWarnStyle.Render("  ejecutando... (cada paso se muestra en la terminal; Enter al terminar cada uno)"))
	case installerDone:
		done, failed := 0, 0
		for _, s := range m.steps {
			switch s.status {
			case "done":
				done++
			case "failed":
				failed++
			}
		}
		b.WriteString(fmt.Sprintf("  %s  %s   ·  enter/r para volver a empezar · esc volver",
			instOKStyle.Render(fmt.Sprintf("%d ok", done)), instFailStyle.Render(fmt.Sprintf("%d con error", failed))))
	}
	b.WriteString("\n")
	return b.String()
}

func firstLine(s string) string {
	if i := strings.Index(s, "\n"); i >= 0 {
		return s[:i]
	}
	return s
}
