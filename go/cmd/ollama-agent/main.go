package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/agent/apply"
	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/snapshot"
	"github.com/jordenparker/claude-custom/go/internal/agent/ui"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

const brewConflict = "brew services also runs llama.cpp; -apply stops it, or run: brew services stop llama.cpp"

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
	sessionDir, err := sessionDir()
	if err != nil {
		return err
	}
	path := flag.String("file", defaultPath, "LaunchAgent plist to edit")
	serverINI := flag.String("server-ini", "", "server.ini with the recommended settings")
	overrides := flag.String("overrides", filepath.Join(sessionDir, "presets", "server.local.ini"), "your settings, laid over server.ini")
	presets := flag.String("presets", filepath.Join(sessionDir, "presets", "models.ini"), "user preset file the router reads")
	render := flag.String("render", "", "bin/ollama-profiles, run with --user-presets after a change")
	program := flag.String("llama-server", "", "llama-server binary the agent runs (default: $LLAMA_SERVER_BIN, else llama-server on PATH)")
	applyOnly := flag.Bool("apply", false, "write the agent from the settings and reload it, without the menu")
	jsonOnly := flag.Bool("json", false, "print the settings as JSON and exit")
	var assignments []string
	flag.Func("set", "KEY=value to write into your settings, render the presets and reload, without the menu (repeatable)", func(text string) error {
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
	recommended, err := variables.Load(*serverINI)
	if err != nil {
		return fmt.Errorf("reading %s: %w", *serverINI, err)
	}
	config := newConfig(*path, *overrides, *presets, *render, serverProgram(*program), sessionDir, recommended)
	if *jsonOnly {
		return printSnapshot(config, os.Stdout)
	}
	if len(sets) > 0 {
		return writeAgent(config, func() error { return apply.Set(config.Setup, sets, os.Stdout) })
	}
	if *applyOnly {
		return writeAgent(config, func() error { return apply.Agent(config.Setup, os.Stdout) })
	}
	model, err := ui.New(config)
	if err != nil {
		return err
	}
	_, err = tea.NewProgram(model).Run()
	return err
}

func sessionDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".claude-ollama"), nil
}

func serverProgram(flagValue string) string {
	if flagValue != "" {
		return flagValue
	}
	if fromEnv := os.Getenv("LLAMA_SERVER_BIN"); fromEnv != "" {
		return fromEnv
	}
	found, err := exec.LookPath("llama-server")
	if err != nil {
		return ""
	}
	return found
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

func newConfig(path, overrides, presets, render, program, sessionDir string, recommended map[string]string) ui.Config {
	uid := os.Getuid()
	logDir := filepath.Join(sessionDir, "logs")
	return ui.Config{
		Setup: apply.Setup{
			Path: path,
			Server: launchd.Server{
				Program: program,
				Presets: presets,
				LogFile: filepath.Join(logDir, "llama-server.log"),
				LogPath: filepath.Join(logDir, "llama-server.stdout.log"),
			},
			Recommended:   recommended,
			OverridesPath: overrides,
			Render:        renderCommand(render, presets),
			Reload:        func() *exec.Cmd { return launchd.ReloadCommand(path, uid) },
			StopBrew:      func() *exec.Cmd { return exec.Command("brew", "services", "stop", "llama.cpp") },
			BrewLoaded:    launchd.BrewLoaded(uid),
		},
		Conflicts: conflicts(uid),
	}
}

func renderCommand(render, presets string) func() *exec.Cmd {
	return func() *exec.Cmd {
		if render == "" {
			return exec.Command("true")
		}
		return exec.Command(render, "--user-presets", "--out", presets)
	}
}

func printSnapshot(config ui.Config, out io.Writer) error {
	state, err := snapshot.Build(config.Path, config.OverridesPath, config.Recommended, config.Conflicts)
	if err != nil {
		return err
	}
	encoder := json.NewEncoder(out)
	encoder.SetIndent("", "  ")
	return encoder.Encode(state)
}

func writeAgent(config ui.Config, write func() error) error {
	if runtime.GOOS != "darwin" {
		return fmt.Errorf("-apply and -set need launchd (macOS); start llama-server --models-preset %s yourself", config.Server.Presets)
	}
	return write()
}

func conflicts(uid int) []string {
	if launchd.BrewLoaded(uid) {
		return []string{brewConflict}
	}
	return nil
}
