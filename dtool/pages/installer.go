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

// Installer: elige que instalar y que autenticar, y corre los pasos EN ORDEN,
// cada uno como proceso visible (tea.ExecProcess), asi que los que preguntan
// —sudo, `gh auth login`, `mcporter auth` con su navegador— se ven y se
// contestan como en una terminal normal.
//
// Estructura: pasos de instalacion, y debajo de algunos sus sub-pasos de
// autenticacion (gh bajo "opencode config"; un `mcporter auth <server>` por
// cada servidor del catalogo bajo "mcporter"). Marcar un sub-paso marca al
// padre si su binario aun no esta instalado.
//
// REGLA DURA: mirar el estado NUNCA autentica. El estado de cada MCP se lee de
// ~/.mcporter/credentials.json en local (una entrada con `tokens` = hay
// sesion). No se llama a mcporter para sondear: `mcporter list --status`, aun
// con --no-oauth segun version/estado, acabo abriendo el navegador para cada
// servidor al entrar en esta pagina (2026-09-21, dos veces). Ver installer_test.go.

type installerState int

const (
	installerSelect installerState = iota
	installerConfirm
	installerRunning
	installerDone
)

type installStep struct {
	key      string // identificador estable: "opencode", "mcporter", "auth:notion"...
	parent   string // key del paso padre, "" si es de primer nivel
	title    string
	desc     string
	cmd      string // se ejecuta con sh -c desde la raiz del repo
	needs    string // binario que el paso necesita en PATH ("mcporter", "gh"); vacio = ninguno
	mcp      string // nombre del servidor MCP si el paso es un auth
	selected bool
	status   string // "", "running", "done", "failed", "skipped"
	note     string
}

type InstallerModel struct {
	state    installerState
	cursor   int
	steps    []installStep
	queue    []int
	repo     string
	repoErr  string
	dryRun   bool
	mcpAuth  map[string]bool // server -> hay tokens guardados (lectura local)
	credPath string
}

type installStepDoneMsg struct {
	index int
	err   error
}

var (
	instGroupStyle = lipgloss.NewStyle().PaddingLeft(2).Foreground(lipgloss.Color("#A78BFA")).Bold(true)
	instOKStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("#34D399"))
	instWarnStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#FBBF24"))
	instFailStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#F87171"))
)

func NewInstallerModel() InstallerModel {
	home, _ := os.UserHomeDir()
	m := InstallerModel{credPath: filepath.Join(home, ".mcporter", "credentials.json")}
	m.repo, m.repoErr = findRepoRoot()
	m.steps = buildSteps(m.mcpServers())
	m.mcpAuth = readMCPAuth(m.credPath)
	return m
}

// buildSteps arma la lista: cada padre seguido de sus hijos, en el orden en
// que deben ejecutarse.
func buildSteps(mcpServers []string) []installStep {
	steps := []installStep{
		{key: "opencode", title: "opencode config", desc: "symlinks ~/.config/opencode + gh (make install_opencode)", cmd: "make install_opencode"},
		{key: "auth:gh", parent: "opencode", needs: "gh", title: "gh auth login", desc: "GitHub, una vez por maquina; abre el navegador", cmd: "gh auth login"},
		{key: "mcporter", title: "mcporter (MCP por bash)", desc: "instala mcporter y enlaza el catalogo de servidores; NO autentica nada (make install_mcporter)", cmd: "make install_mcporter"},
	}
	for _, s := range mcpServers {
		steps = append(steps, installStep{
			key: "auth:" + s, parent: "mcporter", needs: "mcporter", mcp: s,
			title: "auth " + s,
			desc:  "mcporter auth " + s + " — abre el navegador; el token queda en ~/.mcporter",
			cmd:   "mcporter auth " + s,
		})
	}
	steps = append(steps,
		installStep{key: "herdr", title: "herdr", desc: "runtime persistente para agentes: binario, config, integraciones (make install_herdr)", cmd: "make install_herdr"},
		installStep{key: "nvim", title: "Neovim", desc: "Xcode CLT / Homebrew / neovim + nvim-config (make install_nvim YES=1)", cmd: "make install_nvim YES=1"},
	)
	return steps
}

// readMCPAuth: que servidores tienen sesion guardada, leyendo SOLO el fichero
// local de credenciales de mcporter. Sin red, sin OAuth, sin navegador.
func readMCPAuth(credPath string) map[string]bool {
	out := map[string]bool{}
	raw, err := os.ReadFile(credPath)
	if err != nil {
		return out
	}
	var cred struct {
		Entries map[string]struct {
			ServerName string          `json:"serverName"`
			Tokens     json.RawMessage `json:"tokens"`
		} `json:"entries"`
	}
	if json.Unmarshal(raw, &cred) != nil {
		return out
	}
	for key, e := range cred.Entries {
		name := e.ServerName
		if name == "" {
			name = strings.SplitN(key, "|", 2)[0]
		}
		if len(e.Tokens) > 0 && string(e.Tokens) != "null" {
			out[name] = true
		}
	}
	return out
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

// Init no lanza nada: todo el estado que se muestra se leyo en local al crear
// el modelo. (Antes lanzaba sondas de red a mcporter; ver la cabecera.)
func (m InstallerModel) Init() tea.Cmd { return nil }

func installed(bin string) bool {
	if bin == "" {
		return true
	}
	_, err := exec.LookPath(bin)
	return err == nil
}

func (m InstallerModel) indexOf(key string) int {
	for i, s := range m.steps {
		if s.key == key {
			return i
		}
	}
	return -1
}

func (m InstallerModel) Update(msg tea.Msg) (InstallerModel, tea.Cmd) {
	switch msg := msg.(type) {
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
				return fresh, nil
			}
		}
	}
	return m, nil
}

// toggle marca/desmarca un paso. Marcar un hijo cuyo binario no esta
// instalado marca tambien al padre (que es quien lo instala); desmarcar un
// padre desmarca a sus hijos.
func (m *InstallerModel) toggle(i int) {
	s := &m.steps[i]
	s.selected = !s.selected
	if s.selected && s.parent != "" && !installed(s.needs) {
		if p := m.indexOf(s.parent); p >= 0 {
			m.steps[p].selected = true
		}
	}
	if !s.selected && s.parent == "" {
		for j := range m.steps {
			if m.steps[j].parent == s.key {
				m.steps[j].selected = false
			}
		}
	}
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
		m.toggle(m.cursor)
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
		// solo lo pendiente: instalaciones + gh si no hay sesion. Los auth de
		// MCP NO: cada uno abre el navegador y se eligen a mano.
		for i := range m.steps {
			s := &m.steps[i]
			switch {
			case s.parent == "":
				s.selected = true
			case s.key == "auth:gh":
				_, err := runner.Run("gh", "auth", "status")
				s.selected = installed("gh") && err != nil
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
		m.mcpAuth = readMCPAuth(m.credPath)
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
	b.WriteString(instGroupStyle.Render("Instalar / autenticar (los sub-pasos abren el navegador)"))
	b.WriteString("\n")
	for i, s := range m.steps {
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
			state = descStyle.Render("  " + firstLine(s.note))
		}
		if s.mcp != "" {
			if m.mcpAuth[s.mcp] {
				state += instOKStyle.Render("  sesion guardada")
			} else {
				state += instWarnStyle.Render("  sin autenticar")
			}
		}
		if s.needs != "" && !installed(s.needs) {
			state += descStyle.Render("  (instala antes el padre; se marca solo)")
		}
		indent := ""
		if s.parent != "" {
			indent = "    └ "
		}
		line := fmt.Sprintf("%s%s %s%s", indent, box, s.title, state)
		if i == m.cursor && m.state == installerSelect {
			b.WriteString(selectedStyle.Render("› " + line))
		} else {
			b.WriteString(normalStyle.Render("  " + line))
		}
		b.WriteString("\n")
		if s.parent == "" {
			b.WriteString(descStyle.Render(s.desc))
			b.WriteString("\n")
		}
	}
	b.WriteString("\n")
	b.WriteString(descStyle.Render("La limpieza de disco esta en System Cleaner (menu principal) o make clean_disk."))
	b.WriteString("\n\n")
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
		b.WriteString(descStyle.Render("space/x marcar · a todo/nada · p lo pendiente (sin auth de MCP) · enter revisar y confirmar · esc volver"))
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
