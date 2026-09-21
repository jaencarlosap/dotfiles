package pages

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// El fallo real (2026-09-21): abrir el instalador disparaba el OAuth de cada
// MCP porque el estado se sondeaba llamando a mcporter. Estos tests certifican
// que el estado sale de un fichero local y que NINGUN camino de la pagina —
// crear el modelo, Init, marcar, `p`, confirmar — ejecuta mcporter.

// fakeMCPorter pone en PATH un `mcporter` que deja un marcador si alguien lo
// invoca. Devuelve la ruta del marcador.
func fakeMCPorter(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	marker := filepath.Join(dir, "MCPORTER_WAS_CALLED")
	script := "#!/bin/sh\necho \"$@\" >> '" + marker + "'\necho 'OAuth authorization required. Waiting for browser approval...'\nexit 1\n"
	if err := os.WriteFile(filepath.Join(dir, "mcporter"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	// gh falso tambien: `p` consulta `gh auth status`; que no dependa de la maquina.
	if err := os.WriteFile(filepath.Join(dir, "gh"), []byte("#!/bin/sh\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return marker
}

func writeCreds(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "credentials.json")
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestReadMCPAuthUsesOnlyTheLocalFile(t *testing.T) {
	marker := fakeMCPorter(t)
	creds := writeCreds(t, `{"version":1,"entries":{
	  "notion|98e6":{"serverName":"notion","tokens":{"accessToken":"x","refreshToken":"y"}},
	  "quantfury|023c":{"serverName":"quantfury","clientInfo":{"client_id":"k"},"codeVerifier":"v"},
	  "legacy|1234":{"tokens":{"accessToken":"z"}}
	}}`)
	got := readMCPAuth(creds)
	if !got["notion"] {
		t.Fatalf("notion tiene tokens y no se marco: %v", got)
	}
	if got["quantfury"] {
		t.Fatalf("quantfury tiene un OAuth a medias (sin tokens) y se dio por autenticado: %v", got)
	}
	if !got["legacy"] {
		t.Fatalf("una entrada sin serverName debe usar el prefijo de la clave: %v", got)
	}
	if _, err := os.Stat(marker); err == nil {
		t.Fatal("readMCPAuth invoco a mcporter: eso es lo que abria el navegador")
	}
	if len(readMCPAuth(filepath.Join(t.TempDir(), "missing.json"))) != 0 {
		t.Fatal("sin fichero de credenciales, nada esta autenticado")
	}
}

func TestInstallerNeverRunsMCPorterWhileBrowsing(t *testing.T) {
	marker := fakeMCPorter(t)
	m := InstallerModel{credPath: writeCreds(t, `{"entries":{}}`), repo: t.TempDir()}
	m.steps = buildSteps([]string{"atlassian", "notion", "quantfury"})
	m.mcpAuth = readMCPAuth(m.credPath)

	if cmd := m.Init(); cmd != nil {
		t.Fatal("Init devolvio un comando: la pagina no debe lanzar nada al abrirse")
	}
	// Recorrer y marcar todo, usar `p`, abrir la confirmacion y cancelarla.
	keys := []string{"j", "j", " ", "j", "x", "a", "a", "p", "enter", "n"}
	for _, k := range keys {
		var msg tea.KeyMsg
		switch k {
		case "enter":
			msg = tea.KeyMsg{Type: tea.KeyEnter}
		case " ":
			msg = tea.KeyMsg{Type: tea.KeySpace}
		default:
			msg = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(k)}
		}
		var cmd tea.Cmd
		m, cmd = m.Update(msg)
		if cmd != nil {
			t.Fatalf("la tecla %q devolvio un comando en modo seleccion; nada debe ejecutarse antes de confirmar", k)
		}
	}
	m.View()
	if _, err := os.Stat(marker); err == nil {
		out, _ := os.ReadFile(marker)
		t.Fatalf("mcporter fue invocado al navegar por el instalador:\n%s", out)
	}
}

func TestMCPAuthStepsHangUnderMCPorterAndMaintenanceIsGone(t *testing.T) {
	fakeMCPorter(t)
	steps := buildSteps([]string{"notion", "quantfury"})
	parentIdx := -1
	for i, s := range steps {
		if s.key == "mcporter" {
			parentIdx = i
		}
		if s.mcp != "" && s.parent != "mcporter" {
			t.Fatalf("auth %s no cuelga de mcporter: parent=%q", s.mcp, s.parent)
		}
		if s.key == "auth:gh" && s.parent != "opencode" {
			t.Fatalf("gh auth debe colgar de opencode config: parent=%q", s.parent)
		}
		if strings.Contains(strings.ToLower(s.title), "limpieza") || strings.Contains(s.cmd, "clean_disk") {
			t.Fatalf("la limpieza de disco no va en el instalador (tiene su pagina): %q", s.title)
		}
	}
	if parentIdx < 0 {
		t.Fatal("falta el paso mcporter")
	}
	for i, s := range steps {
		if s.mcp != "" && i < parentIdx {
			t.Fatalf("auth %s aparece antes que su padre: el orden de ejecucion seria incorrecto", s.mcp)
		}
	}
}

func TestSelectingAnMCPAuthMarksMCPorterWhenMissing(t *testing.T) {
	// PATH sin mcporter: marcar un auth debe marcar tambien al padre que lo instala.
	t.Setenv("PATH", t.TempDir())
	m := InstallerModel{repo: t.TempDir(), mcpAuth: map[string]bool{}}
	m.steps = buildSteps([]string{"quantfury"})
	authIdx := m.indexOf("auth:quantfury")
	m.toggle(authIdx)
	if !m.steps[m.indexOf("mcporter")].selected {
		t.Fatal("marcar 'auth quantfury' sin mcporter instalado no marco el paso mcporter")
	}
	// Desmarcar el padre desmarca a los hijos.
	m.toggle(m.indexOf("mcporter"))
	if m.steps[authIdx].selected {
		t.Fatal("desmarcar mcporter dejo marcado su auth")
	}
	// `p` nunca marca un auth de MCP: cada uno abre el navegador.
	m.steps[authIdx].selected = true
	m, _ = m.updateSelect(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("p")})
	if m.steps[authIdx].selected {
		t.Fatal("`p` (lo pendiente) marco un auth de MCP")
	}
}

func TestEnterConfirmsBeforeRunning(t *testing.T) {
	fakeMCPorter(t)
	m := InstallerModel{repo: t.TempDir(), mcpAuth: map[string]bool{}, dryRun: true}
	m.steps = buildSteps(nil)
	m.toggle(0)
	m, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd != nil || m.state != installerConfirm {
		t.Fatalf("enter debe llevar a la confirmacion sin ejecutar; state=%v cmd=%v", m.state, cmd)
	}
	if !strings.Contains(m.View(), "Se va a ejecutar, en este orden:") || !strings.Contains(m.View(), "make install_opencode") {
		t.Fatal("la confirmacion no lista lo que va a correr")
	}
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("n")})
	if m.state != installerSelect || !m.steps[0].selected {
		t.Fatal("`n` debe volver a la lista con la seleccion intacta")
	}
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("y")})
	if m.state != installerDone || m.steps[0].status != "skipped" {
		t.Fatalf("con dry-run, `y` debe recorrer la cola sin ejecutar: state=%v status=%q", m.state, m.steps[0].status)
	}
}
