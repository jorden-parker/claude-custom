package apply

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
)

func succeeding() *exec.Cmd {
	return exec.Command("true")
}

func failing() *exec.Cmd {
	return exec.Command("sh", "-c", "echo bootstrap refused; exit 1")
}

func touching(path string) func() *exec.Cmd {
	return func() *exec.Cmd {
		return exec.Command("touch", path)
	}
}

func newSetup(t *testing.T) Setup {
	t.Helper()
	return Setup{
		Path:      filepath.Join(t.TempDir(), "local.ollama.plist"),
		Agent:     launchd.Agent{Label: launchd.Label, Program: "/opt/homebrew/bin/ollama", LogPath: "/tmp/ollama.log"},
		ServerEnv: map[string]string{"OLLAMA_KEEP_ALIVE": "30m", "OLLAMA_MAX_LOADED_MODELS": "2"},
		Reload:    succeeding,
		StopBrew:  succeeding,
	}
}

func savedEnv(t *testing.T, path string) map[string]string {
	t.Helper()
	env, found, err := launchd.Load(path)
	if err != nil || !found {
		t.Fatalf("loading %s: found=%v err=%v", path, found, err)
	}
	return env
}

func TestServerEnvCreatesTheAgentWithServerEnvValues(t *testing.T) {
	setup := newSetup(t)
	var out strings.Builder
	if err := ServerEnv(setup, &out); err != nil {
		t.Fatal(err)
	}
	env := savedEnv(t, setup.Path)
	if env["OLLAMA_KEEP_ALIVE"] != "30m" || env["OLLAMA_MAX_LOADED_MODELS"] != "2" {
		t.Fatalf("env %v", env)
	}
	if !strings.Contains(out.String(), "OLLAMA_KEEP_ALIVE OLLAMA_MAX_LOADED_MODELS") {
		t.Fatalf("output %q", out.String())
	}
}

func TestServerEnvKeepsOtherAgentValues(t *testing.T) {
	setup := newSetup(t)
	agent := setup.Agent
	agent.Env = map[string]string{"OLLAMA_DEBUG": "1", "OLLAMA_KEEP_ALIVE": "5m"}
	if err := launchd.Save(setup.Path, agent); err != nil {
		t.Fatal(err)
	}
	if err := ServerEnv(setup, &strings.Builder{}); err != nil {
		t.Fatal(err)
	}
	env := savedEnv(t, setup.Path)
	if env["OLLAMA_DEBUG"] != "1" || env["OLLAMA_KEEP_ALIVE"] != "30m" {
		t.Fatalf("env %v", env)
	}
}

func TestServerEnvRefusesWhileTheAppRuns(t *testing.T) {
	setup := newSetup(t)
	setup.AppRunning = true
	if err := ServerEnv(setup, &strings.Builder{}); !errors.Is(err, ErrAppRunning) {
		t.Fatalf("got %v", err)
	}
	if _, err := os.Stat(setup.Path); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("agent written while the app runs")
	}
}

func TestServerEnvStopsTheBrewService(t *testing.T) {
	setup := newSetup(t)
	marker := filepath.Join(t.TempDir(), "brew-stopped")
	setup.BrewLoaded = true
	setup.StopBrew = touching(marker)
	if err := ServerEnv(setup, &strings.Builder{}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Fatal("brew service not stopped")
	}
}

func TestServerEnvLeavesBrewAloneWhenNotLoaded(t *testing.T) {
	setup := newSetup(t)
	marker := filepath.Join(t.TempDir(), "brew-stopped")
	setup.StopBrew = touching(marker)
	if err := ServerEnv(setup, &strings.Builder{}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("brew service stopped although it was not loaded")
	}
}

func TestServerEnvReportsAFailedReload(t *testing.T) {
	setup := newSetup(t)
	setup.Reload = failing
	err := ServerEnv(setup, &strings.Builder{})
	if err == nil || !strings.Contains(err.Error(), "bootstrap refused") {
		t.Fatalf("got %v", err)
	}
}
