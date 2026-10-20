package ui

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

var serverEnv = map[string]string{"OLLAMA_KEEP_ALIVE": "30m", "OLLAMA_FLASH_ATTENTION": "1"}

func newConfig(t *testing.T) Config {
	return Config{
		Agent:     launchd.Agent{Label: launchd.Label, Program: "/opt/homebrew/bin/ollama"},
		Path:      filepath.Join(t.TempDir(), "local.ollama.plist"),
		ServerEnv: serverEnv,
		Reload:    func() *exec.Cmd { return exec.Command("true") },
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

func savedEnv(t *testing.T, path string) map[string]string {
	env, found, err := launchd.Load(path)
	if err != nil || !found {
		t.Fatalf("load %s: %v, %v", path, found, err)
	}
	return env
}

func TestWithoutAnAgentStartsFromServerEnvAndIsDirty(t *testing.T) {
	m := newModel(t, newConfig(t))
	if m.values["OLLAMA_KEEP_ALIVE"] != "30m" || !m.dirty() {
		t.Fatalf("values %v, dirty %v", m.values, m.dirty())
	}
}

func TestExistingAgentValuesWin(t *testing.T) {
	config := newConfig(t)
	if err := launchd.Save(config.Path, launchd.Agent{Label: "x", Program: "y", Env: map[string]string{"OLLAMA_KEEP_ALIVE": "-1"}}); err != nil {
		t.Fatal(err)
	}
	m := newModel(t, config)
	if m.values["OLLAMA_KEEP_ALIVE"] != "-1" || m.dirty() {
		t.Fatalf("values %v, dirty %v", m.values, m.dirty())
	}
}

func TestBrokenAgentFileIsAnError(t *testing.T) {
	config := newConfig(t)
	if err := os.WriteFile(config.Path, []byte("<plist><dict><key>EnvironmentVariables</key>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := New(config); err == nil {
		t.Fatal("expected an error")
	}
}

func TestEditingAValueThenSavingWritesThePlist(t *testing.T) {
	config := newConfig(t)
	m := newModel(t, config)
	m, _ = press(m, "enter")
	for range len("30m") {
		m, _ = press(m, "backspace")
	}
	m = typeText(m, "-1")
	m, _ = press(m, "enter", "w")
	if got := savedEnv(t, config.Path)["OLLAMA_KEEP_ALIVE"]; got != "-1" {
		t.Fatalf("saved %q", got)
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
	if m.values["OLLAMA_MAX_LOADED_MODELS"] != "qwx" {
		t.Fatalf("got %q", m.values["OLLAMA_MAX_LOADED_MODELS"])
	}
}

func TestEscCancelsTheEdit(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, _ = press(m, "enter")
	m = typeText(m, "9")
	m, _ = press(m, "esc")
	if m.editing || m.values["OLLAMA_KEEP_ALIVE"] != "30m" {
		t.Fatalf("editing %v, value %q", m.editing, m.values["OLLAMA_KEEP_ALIVE"])
	}
}

func TestClearingAValueUnsetsIt(t *testing.T) {
	config := newConfig(t)
	m := newModel(t, config)
	m, _ = press(m, "x", "w")
	if _, set := savedEnv(t, config.Path)["OLLAMA_KEEP_ALIVE"]; set {
		t.Fatal("OLLAMA_KEEP_ALIVE still set")
	}
}

func TestResetRestoresTheServerEnvValue(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, _ = press(m, "x", "r")
	if m.values["OLLAMA_KEEP_ALIVE"] != "30m" {
		t.Fatalf("got %q", m.values["OLLAMA_KEEP_ALIVE"])
	}
}

func TestResetWithoutServerEnvValueUnsets(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, _ = press(m, "down", "enter")
	m = typeText(m, "3")
	m, _ = press(m, "enter", "r")
	if _, set := m.values["OLLAMA_MAX_LOADED_MODELS"]; set {
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
	savedEnv(t, config.Path)
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
	config.Conflicts = []string{"brew services is also running ollama"}
	m := newModel(t, config)
	view := ansi.Strip(m.View().Content)
	for _, want := range []string{"OLLAMA_KEEP_ALIVE", "30m", variables.Summary("OLLAMA_KEEP_ALIVE"), "brew services is also running ollama", config.Path} {
		if !strings.Contains(view, want) {
			t.Errorf("missing %q in\n%s", want, view)
		}
	}
}

func TestViewMarksValuesThatDifferFromServerEnv(t *testing.T) {
	m := newModel(t, newConfig(t))
	m, _ = press(m, "x")
	if view := ansi.Strip(m.View().Content); !strings.Contains(view, "server.env: 30m") {
		t.Fatalf("missing server.env hint in\n%s", view)
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
