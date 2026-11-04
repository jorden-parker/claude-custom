package ui

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/jordenparker/claude-custom/go/internal/agent/apply"
	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

var recommended = map[string]string{"cache-type-k": "q8_0", "models-max": "2"}

func newConfig(t *testing.T) Config {
	dir := t.TempDir()
	t.Setenv("CLAUDE_CONSOLE_STATE_DIR", t.TempDir())
	return Config{
		Setup: apply.Setup{
			Path: filepath.Join(dir, "local.llama-server.plist"),
			Server: launchd.Server{
				Program: "/opt/homebrew/bin/llama-server",
				Presets: filepath.Join(dir, "models.ini"),
				LogFile: filepath.Join(dir, "logs", "llama-server.log"),
			},
			Recommended:   recommended,
			OverridesPath: filepath.Join(dir, "server.local.ini"),
			Render:        func() *exec.Cmd { return exec.Command("true") },
			Reload:        func() *exec.Cmd { return exec.Command("true") },
		},
	}
}

func newModel(t *testing.T, config Config) Model {
	m, err := New(config)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func press(m Model, keys ...string) (Model, tea.Cmd) {
	var cmd tea.Cmd
	for _, k := range keys {
		var msg tea.KeyPressMsg
		switch k {
		case "down":
			msg = tea.KeyPressMsg{Code: tea.KeyDown}
		case "enter":
			msg = tea.KeyPressMsg{Code: tea.KeyEnter}
		case "esc":
			msg = tea.KeyPressMsg{Code: tea.KeyEscape}
		case "backspace":
			msg = tea.KeyPressMsg{Code: tea.KeyBackspace}
		default:
			msg = tea.KeyPressMsg{Code: rune(k[0]), Text: k}
		}
		updated, next := m.Update(msg)
		m, cmd = updated.(Model), next
	}
	return m, cmd
}

func typeText(m Model, text string) Model {
	for _, r := range text {
		m, _ = press(m, string(r))
	}
	return m
}

func savedOverrides(t *testing.T, config Config) map[string]string {
	overrides, err := variables.Load(config.OverridesPath)
	if err != nil {
		t.Fatal(err)
	}
	return overrides
}

func savedModelsMax(t *testing.T, config Config) string {
	value, found, err := launchd.ModelsMax(config.Path)
	if err != nil || !found {
		t.Fatalf("models-max: %v, %v", found, err)
	}
	return value
}

func TestWithoutAnAgentStartsFromTheRecommendedValuesAndIsDirty(t *testing.T) {
	m := newModel(t, newConfig(t))
	if m.values["cache-type-k"] != "q8_0" || !m.dirty() {
		t.Fatalf("values %v, dirty %v", m.values, m.dirty())
	}
}

func TestOverridesWin(t *testing.T) {
	config := newConfig(t)
	if err := variables.Save(config.OverridesPath, map[string]string{"cache-type-k": "f16"}); err != nil {
		t.Fatal(err)
	}
	if _, err := apply.Save(config.Setup, map[string]string{"cache-type-k": "f16", "models-max": "2"}); err != nil {
		t.Fatal(err)
	}
	m := newModel(t, config)
	if m.values["cache-type-k"] != "f16" || m.dirty() {
		t.Fatalf("values %v, dirty %v", m.values, m.dirty())
	}
}

func TestBrokenOverridesFileIsAnError(t *testing.T) {
	config := newConfig(t)
	if err := os.WriteFile(config.OverridesPath, []byte("[*]\nbroken\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := New(config); err == nil {
		t.Fatal("expected an error")
	}
}

func TestEditingModelsMaxThenSavingWritesTheOverrideAndThePlist(t *testing.T) {
	config := newConfig(t)
	m := newModel(t, config)
	m, _ = press(m, "enter", "backspace")
	m = typeText(m, "3")
	m, _ = press(m, "enter", "w")
	if got := savedOverrides(t, config)["models-max"]; got != "3" {
		t.Fatalf("saved %q", got)
	}
	if got := savedModelsMax(t, config); got != "3" {
		t.Fatalf("plist models-max %q", got)
	}
	if m.dirty() {
		t.Fatal("still dirty after save")
	}
}

func TestTypedLettersGoToTheInputNotTheKeymap(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, _ = press(m, "down", "enter")
	m = typeText(m, "qwx")
	m, _ = press(m, "enter")
	if m.values["n-gpu-layers"] != "qwx" {
		t.Fatalf("got %q", m.values["n-gpu-layers"])
	}
}

func TestEscCancelsTheEdit(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, _ = press(m, "enter")
	m = typeText(m, "9")
	m, _ = press(m, "esc")
	if m.editing || m.values["models-max"] != "2" {
		t.Fatalf("editing %v, value %q", m.editing, m.values["models-max"])
	}
}

func TestResetRestoresTheRecommendedValue(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, _ = press(m, "enter", "backspace")
	m = typeText(m, "4")
	m, _ = press(m, "enter", "r")
	if m.values["models-max"] != "2" {
		t.Fatalf("got %q", m.values["models-max"])
	}
}

func TestResetWithoutRecommendedValueUnsets(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, _ = press(m, "down", "enter")
	m = typeText(m, "3")
	m, _ = press(m, "enter", "r")
	if _, set := m.values["n-gpu-layers"]; set {
		t.Fatal("still set")
	}
}

func TestApplySavesThenReloads(t *testing.T) {
	config := newConfig(t)
	reloaded := false
	config.Reload = func() *exec.Cmd {
		reloaded = true
		return exec.Command("true")
	}
	m := newModel(t, config)
	m, cmd := press(m, "a")
	if cmd == nil {
		t.Fatal("expected a reload command")
	}
	updated, _ := m.Update(cmd())
	m = updated.(Model)
	if !reloaded || !strings.Contains(m.status, "reloaded") {
		t.Fatalf("reloaded %v, status %q", reloaded, m.status)
	}
	savedModelsMax(t, config)
}

func TestFailedReloadShowsLaunchctlOutput(t *testing.T) {
	config := newConfig(t)
	config.Reload = func() *exec.Cmd { return exec.Command("sh", "-c", "echo 'Bootstrap failed: 5' >&2; exit 5") }
	m, cmd := press(newModel(t, config), "a")
	updated, _ := m.Update(cmd())
	if status := updated.(Model).status; !strings.Contains(status, "Bootstrap failed: 5") {
		t.Fatalf("status %q", status)
	}
}

func TestQuitWithUnsavedChangesAsksFirst(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, cmd := press(m, "q")
	if cmd != nil || !strings.Contains(m.status, "Unsaved") {
		t.Fatalf("status %q", m.status)
	}
	if _, cmd = press(m, "q"); cmd == nil {
		t.Fatal("second q should quit")
	}
}

func TestCursorStaysInRange(t *testing.T) {
	m := newModel(t, newConfig(t))
	for range len(variables.Known) + 5 {
		m, _ = press(m, "down")
	}
	if m.cursor != len(m.names)-1 {
		t.Fatalf("cursor %d of %d", m.cursor, len(m.names))
	}
}

func TestViewShowsValuesSummariesAndConflicts(t *testing.T) {
	config := newConfig(t)
	config.Conflicts = []string{"brew services is also running llama.cpp"}
	m := newModel(t, config)
	view := ansi.Strip(m.View().Content)
	for _, want := range []string{"llama-server LaunchAgent", "cache-type-k", "q8_0", variables.Summary("models-max"), "brew services is also running llama.cpp", config.Path} {
		if !strings.Contains(view, want) {
			t.Errorf("missing %q in\n%s", want, view)
		}
	}
}

func TestViewMarksValuesThatDifferFromServerINI(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, _ = press(m, "enter", "backspace")
	m = typeText(m, "5")
	m, _ = press(m, "enter")
	if view := ansi.Strip(m.View().Content); !strings.Contains(view, "server.ini: 2") {
		t.Fatalf("missing server.ini hint in\n%s", view)
	}
}

func TestViewFitsTheWindowWidth(t *testing.T) {
	m := newModel(t, newConfig(t))
	updated, _ := m.Update(tea.WindowSizeMsg{Width: 40, Height: 30})
	for _, line := range strings.Split(updated.(Model).View().Content, "\n") {
		if ansi.StringWidth(line) > 40 {
			t.Fatalf("line wider than 40: %q", ansi.Strip(line))
		}
	}
}
