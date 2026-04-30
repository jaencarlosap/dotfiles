package runner

import (
	"bytes"
	"os/exec"
	"strings"
)

// ShellCmd builds an *exec.Cmd that runs the script via "sh -c". Useful when
// you need shell features like glob expansion, pipes, or && chains.
func ShellCmd(script string) *exec.Cmd {
	return exec.Command("sh", "-c", script)
}

// SudoShellCmd builds an *exec.Cmd that runs the script as root via
// "sudo sh -c". Pair with tea.ExecProcess so the sudo password prompt is
// visible to the user — calling Run/RunWithSudo from inside an altscreen
// TUI will hang.
func SudoShellCmd(script string) *exec.Cmd {
	return exec.Command("sudo", "sh", "-c", script)
}

// ShellQuote returns a single-quoted string safe to embed in a shell command.
func ShellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// Run executes a command and returns its combined output.
func Run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	return strings.TrimSpace(out.String()), err
}

// RunWithSudo executes a command prefixed with sudo.
func RunWithSudo(name string, args ...string) (string, error) {
	sudoArgs := append([]string{name}, args...)
	return Run("sudo", sudoArgs...)
}

// RunSilent executes a command and only returns the error.
func RunSilent(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	return cmd.Run()
}

// CommandExists checks if a command is available in PATH.
func CommandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}
