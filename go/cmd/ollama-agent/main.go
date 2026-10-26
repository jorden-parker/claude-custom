package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"runtime"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/agent/apply"
	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/snapshot"
	"github.com/jordenparker/claude-custom/go/internal/agent/ui"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

const (
	brewConflict = "brew services also runs ollama on the same port; run: brew services stop ollama"
	appConflict  = "the Ollama app is running its own server; quit it from the menu bar"
)

var errUsage = errors.New("usage")

func main() {
	err := run()
	if err == nil {
		return
	}
	fmt.Fprintln(os.Stderr, "ollama-agent:", err)
	if errors.Is(err, errUsage) {
		os.Exit(2)
	}
	os.Exit(1)
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
	applyOnly := flag.Bool("apply", false, "write the server.env values into the agent and reload it, without the menu")
	jsonOnly := flag.Bool("json", false, "print the agent's variables as JSON and exit")
	var assignments []string
	flag.Func("set", "NAME=value to write into the agent and reload it, without the menu (repeatable)", func(text string) error {
		assignments = append(assignments, text)
		return nil
	})
	flag.Parse()

	sets, err := parseAssignments(assignments)
	if err != nil {
		return err
	}
	if err := checkModes(*applyOnly, *jsonOnly, sets); err != nil {
		return err
	}
	config, err := newConfig(*path, *serverEnvPath, *program, logPath)
	if err != nil {
		return err
	}
	if *jsonOnly {
		return printSnapshot(config, os.Stdout)
	}
	if len(sets) > 0 {
		return applyServerEnv(config, sets)
	}
	if *applyOnly {
		return applyServerEnv(config, config.ServerEnv)
	}
	model, err := ui.New(config)
	if err != nil {
		return err
	}
	_, err = tea.NewProgram(model).Run()
	return err
}

func parseAssignments(texts []string) (map[string]string, error) {
	sets := map[string]string{}
	for _, text := range texts {
		name, value, err := variables.ParseAssignment(text)
		if err != nil {
			return nil, err
		}
		sets[name] = value
	}
	return sets, nil
}

func checkModes(applyOnly, jsonOnly bool, sets map[string]string) error {
	if applyOnly && len(sets) > 0 {
		return fmt.Errorf("%w: -set and -apply both write the plist; use one", errUsage)
	}
	if jsonOnly && (applyOnly || len(sets) > 0) {
		return fmt.Errorf("%w: -json only prints; drop -apply and -set", errUsage)
	}
	return nil
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

func printSnapshot(config ui.Config, out io.Writer) error {
	state, err := snapshot.Build(config.Path, config.ServerEnv, config.Conflicts)
	if err != nil {
		return err
	}
	encoder := json.NewEncoder(out)
	encoder.SetIndent("", "  ")
	return encoder.Encode(state)
}

func applyServerEnv(config ui.Config, serverEnv map[string]string) error {
	if runtime.GOOS != "darwin" {
		return fmt.Errorf("-apply and -set need launchd (macOS); start ollama with the values in server.env yourself")
	}
	return apply.ServerEnv(apply.Setup{
		Path:       config.Path,
		Agent:      config.Agent,
		ServerEnv:  serverEnv,
		Reload:     config.Reload,
		StopBrew:   func() *exec.Cmd { return exec.Command("brew", "services", "stop", "ollama") },
		BrewLoaded: brewLoaded(os.Getuid()),
		AppRunning: appRunning(),
	}, os.Stdout)
}

func brewLoaded(uid int) bool {
	return launchd.ServiceLoaded(uid, launchd.BrewLabel)
}

func appRunning() bool {
	return exec.Command("pgrep", "-xq", "Ollama").Run() == nil
}

func conflicts(uid int) []string {
	var found []string
	if brewLoaded(uid) {
		found = append(found, brewConflict)
	}
	if appRunning() {
		found = append(found, appConflict)
	}
	return found
}
