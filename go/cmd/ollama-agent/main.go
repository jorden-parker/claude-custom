package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/ui"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

const (
	brewConflict = "brew services also runs ollama on the same port; run: brew services stop ollama"
	appConflict  = "the Ollama app is running its own server; quit it from the menu bar"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "ollama-agent:", err)
		os.Exit(1)
	}
}

func run() error {
	defaultPath, err := launchd.DefaultPath()
	if err != nil {
		return err
	}
	logPath, err := launchd.DefaultLogPath()
	if err != nil {
		return err
	}
	path := flag.String("file", defaultPath, "LaunchAgent plist to edit")
	serverEnvPath := flag.String("server-env", "", "server.env with the recommended values")
	program := flag.String("ollama", "", "ollama binary the agent runs (default: ollama on PATH)")
	flag.Parse()

	config, err := newConfig(*path, *serverEnvPath, *program, logPath)
	if err != nil {
		return err
	}
	model, err := ui.New(config)
	if err != nil {
		return err
	}
	_, err = tea.NewProgram(model).Run()
	return err
}

func newConfig(path, serverEnvPath, program, logPath string) (ui.Config, error) {
	serverEnv, err := variables.LoadServerEnv(serverEnvPath)
	if err != nil {
		return ui.Config{}, fmt.Errorf("reading %s: %w", serverEnvPath, err)
	}
	if program == "" {
		if program, err = exec.LookPath("ollama"); err != nil {
			return ui.Config{}, fmt.Errorf("ollama not on PATH; pass -ollama: %w", err)
		}
	}
	uid := os.Getuid()
	return ui.Config{
		Agent:     launchd.Agent{Label: launchd.Label, Program: program, LogPath: logPath},
		Path:      path,
		ServerEnv: serverEnv,
		Reload:    func() *exec.Cmd { return launchd.ReloadCommand(path, uid) },
		Conflicts: conflicts(uid),
	}, nil
}

func conflicts(uid int) []string {
	var found []string
	if launchd.ServiceLoaded(uid, launchd.BrewLabel) {
		found = append(found, brewConflict)
	}
	if exec.Command("pgrep", "-xq", "Ollama").Run() == nil {
		found = append(found, appConflict)
	}
	return found
}
