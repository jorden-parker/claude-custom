package apply

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
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
	dir := t.TempDir()
	return Setup{
		Path: filepath.Join(dir, "local.llama-server.plist"),
		Server: launchd.Server{
			Program: "/opt/homebrew/bin/llama-server",
			Presets: filepath.Join(dir, "presets", "models.ini"),
			LogFile: filepath.Join(dir, "logs", "llama-server.log"),
			LogPath: filepath.Join(dir, "logs", "llama-server.stdout.log"),
		},
		Recommended:   map[string]string{"cache-type-k": "q8_0", variables.ModelsMax: "2"},
		OverridesPath: filepath.Join(dir, "presets", "server.local.ini"),
		Render:        succeeding,
		Reload:        succeeding,
		StopBrew:      succeeding,
	}
}

func savedArguments(t *testing.T, path string) []string {
	t.Helper()
	data, found, err := launchd.Load(path)
	if err != nil || !found {
		t.Fatalf("loading %s: found=%v err=%v", path, found, err)
	}
	arguments, err := launchd.ReadArguments(data)
	if err != nil {
		t.Fatal(err)
	}
	return arguments
}

func argumentAfter(arguments []string, flag string) string {
	for i, argument := range arguments {
		if argument == flag && i+1 < len(arguments) {
			return arguments[i+1]
		}
	}
	return ""
}

func TestAgentWritesThePlistWithTheRecommendedModelsMax(t *testing.T) {
	setup := newSetup(t)
	var out strings.Builder
	if err := Agent(setup, &out); err != nil {
		t.Fatal(err)
	}
	arguments := savedArguments(t, setup.Path)
	if argumentAfter(arguments, "--models-max") != "2" || argumentAfter(arguments, "--models-preset") != setup.Server.Presets {
		t.Fatalf("arguments %v", arguments)
	}
	if !strings.Contains(out.String(), "wrote "+setup.Path) || !strings.Contains(out.String(), "reloaded local.llama-server") {
		t.Fatalf("output %q", out.String())
	}
}

func TestAgentMakesTheLogFolder(t *testing.T) {
	setup := newSetup(t)
	if err := Agent(setup, &strings.Builder{}); err != nil {
		t.Fatal(err)
	}
	if info, err := os.Stat(filepath.Dir(setup.Server.LogFile)); err != nil || !info.IsDir() {
		t.Fatalf("log folder: %v", err)
	}
}

func TestAgentUsesTheOverriddenModelsMax(t *testing.T) {
	setup := newSetup(t)
	if err := variables.Save(setup.OverridesPath, map[string]string{variables.ModelsMax: "3"}); err != nil {
		t.Fatal(err)
	}
	if err := Agent(setup, &strings.Builder{}); err != nil {
		t.Fatal(err)
	}
	if got := argumentAfter(savedArguments(t, setup.Path), "--models-max"); got != "3" {
		t.Fatalf("models-max %q", got)
	}
}

func TestAgentReloadsEvenWhenThePlistIsUnchanged(t *testing.T) {
	setup := newSetup(t)
	if err := Agent(setup, &strings.Builder{}); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(t.TempDir(), "reloaded")
	setup.Reload = touching(marker)
	var out strings.Builder
	if err := Agent(setup, &out); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Fatal("not reloaded")
	}
	if !strings.Contains(out.String(), setup.Path+" unchanged") {
		t.Fatalf("output %q", out.String())
	}
}

func TestAgentRefusesWithoutAServerBinary(t *testing.T) {
	setup := newSetup(t)
	setup.Server.Program = ""
	if err := Agent(setup, &strings.Builder{}); !errors.Is(err, ErrNoServer) {
		t.Fatalf("got %v", err)
	}
	if _, err := os.Stat(setup.Path); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("plist written without a server binary")
	}
}

func TestAgentStopsTheBrewService(t *testing.T) {
	setup := newSetup(t)
	marker := filepath.Join(t.TempDir(), "brew-stopped")
	setup.BrewLoaded = true
	setup.StopBrew = touching(marker)
	var out strings.Builder
	if err := Agent(setup, &out); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Fatal("brew service not stopped")
	}
	if !strings.Contains(out.String(), "stopped brew services llama.cpp") {
		t.Fatalf("output %q", out.String())
	}
}

func TestAgentLeavesBrewAloneWhenNotLoaded(t *testing.T) {
	setup := newSetup(t)
	marker := filepath.Join(t.TempDir(), "brew-stopped")
	setup.StopBrew = touching(marker)
	if err := Agent(setup, &strings.Builder{}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("brew service stopped although it was not loaded")
	}
}

func TestAgentReportsAFailedReload(t *testing.T) {
	setup := newSetup(t)
	setup.Reload = failing
	err := Agent(setup, &strings.Builder{})
	if err == nil || !strings.Contains(err.Error(), "bootstrap refused") {
		t.Fatalf("got %v", err)
	}
}

func TestSetWritesTheOverrideRendersThenReloads(t *testing.T) {
	setup := newSetup(t)
	rendered := filepath.Join(t.TempDir(), "rendered")
	setup.Render = touching(rendered)
	var out strings.Builder
	if err := Set(setup, map[string]string{"cache-type-k": "f16", variables.ModelsMax: "3"}, &out); err != nil {
		t.Fatal(err)
	}
	overrides, err := variables.Load(setup.OverridesPath)
	if err != nil || overrides["cache-type-k"] != "f16" || overrides[variables.ModelsMax] != "3" {
		t.Fatalf("overrides %v, %v", overrides, err)
	}
	if _, err := os.Stat(rendered); err != nil {
		t.Fatal("user presets not rendered")
	}
	if got := argumentAfter(savedArguments(t, setup.Path), "--models-max"); got != "3" {
		t.Fatalf("models-max %q", got)
	}
	if !strings.Contains(out.String(), "set cache-type-k models-max") {
		t.Fatalf("output %q", out.String())
	}
}

func TestSetToTheRecommendedValueDropsTheOverride(t *testing.T) {
	setup := newSetup(t)
	if err := variables.Save(setup.OverridesPath, map[string]string{"cache-type-k": "f16", "prio": "1"}); err != nil {
		t.Fatal(err)
	}
	if err := Set(setup, map[string]string{"cache-type-k": "q8_0"}, &strings.Builder{}); err != nil {
		t.Fatal(err)
	}
	overrides, _ := variables.Load(setup.OverridesPath)
	if _, set := overrides["cache-type-k"]; set || overrides["prio"] != "1" {
		t.Fatalf("overrides %v", overrides)
	}
}

func TestSetStopsWhenTheRenderFails(t *testing.T) {
	setup := newSetup(t)
	setup.Render = failing
	if err := Set(setup, map[string]string{"prio": "1"}, &strings.Builder{}); err == nil || !strings.Contains(err.Error(), "rendering the user presets") {
		t.Fatalf("got %v", err)
	}
	if _, err := os.Stat(setup.Path); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("plist written after a failed render")
	}
}
