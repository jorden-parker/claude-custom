package ui

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/jordenparker/claude-custom/tools-tui/catalog"
	"github.com/jordenparker/claude-custom/tools-tui/settings"
)

const docsPage = "| Tool | Description | Permission required |\n| :- | :- | :- |\n" +
	"| `Bash` | Runs commands | Yes |\n" +
	"| `Read` | Reads files | No |\n" +
	"| `Workflow` | Runs workflows | Yes |\n"

type fixture struct {
	settingsPath string
	otherPath    string
	snapshotPath string
	docsURL      string
}

func newFixture(t *testing.T, settingsJSON string, cachedTools ...string) fixture {
	t.Helper()
	dir := t.TempDir()
	f := fixture{
		settingsPath: filepath.Join(dir, "settings.json"),
		otherPath:    filepath.Join(dir, "settings.local.json"),
		snapshotPath: filepath.Join(dir, "cache", "tools.json"),
	}
	os.WriteFile(f.settingsPath, []byte(settingsJSON), 0o644)
	if len(cachedTools) > 0 {
		var tools []catalog.Tool
		for _, name := range cachedTools {
			tools = append(tools, catalog.Tool{Name: name})
		}
		catalog.SaveSnapshot(f.snapshotPath, catalog.Snapshot{Source: "cache", SyncedAt: time.Now(), Tools: tools})
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(docsPage))
	}))
	t.Cleanup(server.Close)
	f.docsURL = server.URL
	return f
}

func (f fixture) model(t *testing.T) Model {
	t.Helper()
	files := []settings.File{{Label: "user", Path: f.settingsPath}, {Label: "local", Path: f.otherPath}}
	m, err := New(Config{SettingsPath: f.settingsPath, SettingsFiles: files, SnapshotPath: f.snapshotPath, DocsURL: f.docsURL})
	if err != nil {
		t.Fatal(err)
	}
	updated, _ := m.Update(tea.WindowSizeMsg{Width: 120, Height: 30})
	return updated.(Model)
}

func press(m Model, keys ...string) Model {
	for _, k := range keys {
		var msg tea.KeyPressMsg
		switch k {
		case "down":
			msg = tea.KeyPressMsg{Code: tea.KeyDown}
		case "enter":
			msg = tea.KeyPressMsg{Code: tea.KeyEnter}
		case "esc":
			msg = tea.KeyPressMsg{Code: tea.KeyEscape}
		case "space":
			msg = tea.KeyPressMsg{Code: tea.KeySpace, Text: " "}
		default:
			msg = tea.KeyPressMsg{Code: rune(k[0]), Text: k}
		}
		updated, _ := m.Update(msg)
		m = updated.(Model)
	}
	return m
}

func runCommand(m Model, cmd tea.Cmd) Model {
	if cmd == nil {
		return m
	}
	updated, _ := m.Update(cmd())
	return updated.(Model)
}

func savedSettings(t *testing.T, f fixture) map[string]settings.ToolState {
	t.Helper()
	data, _ := os.ReadFile(f.settingsPath)
	states, err := settings.Read(data, []string{"Bash", "Read", "Workflow"})
	if err != nil {
		t.Fatal(err)
	}
	return states
}

func TestLoadsCurrentStateFromSettings(t *testing.T) {
	f := newFixture(t, `{"permissions":{"allow":["Read"]}}`, "Bash", "Read")
	m := f.model(t)

	if m.states["Read"].Permission != settings.Allow {
		t.Fatalf("got %+v", m.states)
	}
}

func TestPermissionKeysChangeSelectedTool(t *testing.T) {
	f := newFixture(t, `{}`, "Bash", "Read")
	m := f.model(t)

	cases := map[string]settings.Permission{"a": settings.Allow, "p": settings.Ask, "d": settings.Deny, "r": settings.Default}
	for key, want := range cases {
		m = press(m, key)
		if got := m.states["Bash"].Permission; got != want {
			t.Errorf("%s: got %v", key, got)
		}
	}
}

func TestSpaceCyclesPermission(t *testing.T) {
	m := newFixture(t, `{}`, "Bash").model(t)

	m = press(m, "space", "space")
	if m.states["Bash"].Permission != settings.Ask {
		t.Fatalf("got %v", m.states["Bash"])
	}
}

func TestDisableKeyIsSeparateFromPermission(t *testing.T) {
	m := newFixture(t, `{}`, "Bash", "Read").model(t)

	m = press(m, "down", "a", "x")
	if m.states["Read"] != (settings.ToolState{Permission: settings.Allow, Disabled: true}) {
		t.Fatalf("got %+v", m.states["Read"])
	}
	if m.states["Bash"] != (settings.ToolState{}) {
		t.Fatalf("Bash changed: %+v", m.states["Bash"])
	}
}

func TestSaveWritesSettingsAndPreservesOtherKeys(t *testing.T) {
	f := newFixture(t, `{"model":"opus","permissions":{"allow":["Bash(git log *)"]}}`, "Bash", "Read")
	m := f.model(t)

	m = press(m, "p", "down", "x", "w")

	states := savedSettings(t, f)
	if states["Bash"].Permission != settings.Ask || states["Read"].Permission != settings.Deny {
		t.Fatalf("saved %+v", states)
	}
	data, _ := os.ReadFile(f.settingsPath)
	if !strings.Contains(string(data), `"model": "opus"`) || !strings.Contains(string(data), "Bash(git log *)") {
		t.Fatalf("lost unmanaged settings: %s", data)
	}
	if m.dirty() {
		t.Fatal("model should be clean after saving")
	}
}

func TestSaveKeepsRulesAddedToFileSinceLaunch(t *testing.T) {
	f := newFixture(t, `{}`, "Bash")
	m := f.model(t)
	os.WriteFile(f.settingsPath, []byte(`{"permissions":{"allow":["Bash(npm test)"]}}`), 0o644)

	press(m, "a", "w")

	data, _ := os.ReadFile(f.settingsPath)
	if !strings.Contains(string(data), "Bash(npm test)") {
		t.Fatalf("lost a rule written by another process: %s", data)
	}
}

func TestStartsSyncWhenNoCachedToolList(t *testing.T) {
	f := newFixture(t, `{}`)
	m, _ := New(Config{SettingsPath: f.settingsPath, SnapshotPath: f.snapshotPath, DocsURL: f.docsURL})

	m = runCommand(m, m.Init())
	if len(m.tools) != 3 {
		t.Fatalf("got %d tools", len(m.tools))
	}
	if _, err := catalog.LoadSnapshot(f.snapshotPath); err != nil {
		t.Fatalf("snapshot not cached: %v", err)
	}
}

func TestSyncDropsStaleToolsAndKeepsUnsavedEdits(t *testing.T) {
	f := newFixture(t, `{"permissions":{"ask":["Workflow"]}}`, "Bash", "TaskOutput")
	m := f.model(t)
	m = press(m, "a")

	updated, cmd := m.Update(tea.KeyPressMsg{Code: 'u', Text: "u"})
	m = runCommand(updated.(Model), cmd)

	if m.states["Bash"].Permission != settings.Allow {
		t.Fatal("unsaved edit lost on sync")
	}
	if _, stale := m.states["TaskOutput"]; stale {
		t.Fatal("stale tool kept after sync")
	}
	if m.states["Workflow"].Permission != settings.Ask {
		t.Fatal("new tool did not pick up its saved state")
	}
	if !strings.Contains(m.status, "TaskOutput") {
		t.Fatalf("status should name dropped tools: %q", m.status)
	}
}

func TestQuitWithUnsavedChangesNeedsConfirmation(t *testing.T) {
	m := newFixture(t, `{}`, "Bash").model(t)
	m = press(m, "a")

	updated, cmd := m.Update(tea.KeyPressMsg{Code: 'q', Text: "q"})
	if cmd != nil {
		t.Fatal("quit without confirmation")
	}
	_, cmd = updated.Update(tea.KeyPressMsg{Code: 'q', Text: "q"})
	if cmd == nil {
		t.Fatal("second q should quit")
	}
}

func TestViewShowsStateAndHelp(t *testing.T) {
	m := newFixture(t, `{"permissions":{"allow":["Bash"]}}`, "Bash").model(t)

	content := ansi.Strip(m.View().Content)
	for _, want := range []string{"Bash", "allow", "on", "a allow", "x"} {
		if !strings.Contains(content, want) {
			t.Errorf("view missing %q:\n%s", want, content)
		}
	}
}

func TestFirstSyncDoesNotListEveryToolAsAdded(t *testing.T) {
	f := newFixture(t, `{}`)
	m, _ := New(Config{SettingsPath: f.settingsPath, SnapshotPath: f.snapshotPath, DocsURL: f.docsURL})

	m = runCommand(m, m.Init())
	if m.status != "Synced 3 tools." {
		t.Fatalf("got %q", m.status)
	}
}

func TestViewLinesFitTheWindow(t *testing.T) {
	m := newFixture(t, `{}`, "Bash").model(t)
	m.status = strings.Repeat("long status ", 30)
	updated, _ := m.Update(tea.WindowSizeMsg{Width: 60, Height: 20})

	for _, line := range strings.Split(updated.(Model).View().Content, "\n") {
		if width := ansi.StringWidth(line); width > 60 {
			t.Fatalf("line is %d wide: %q", width, ansi.Strip(line))
		}
	}
}

func TestSwitchingFileLoadsItAndSavesToIt(t *testing.T) {
	f := newFixture(t, `{"permissions":{"allow":["Bash"]}}`, "Bash")
	os.WriteFile(f.otherPath, []byte(`{"permissions":{"ask":["Bash"]}}`), 0o644)
	m := f.model(t)

	m = press(m, "f", "down", "enter")
	if m.states["Bash"].Permission != settings.Ask || m.config.SettingsPath != f.otherPath {
		t.Fatalf("did not switch: %+v %s", m.states, m.config.SettingsPath)
	}
	press(m, "d", "w")

	other, _ := os.ReadFile(f.otherPath)
	user, _ := os.ReadFile(f.settingsPath)
	if !strings.Contains(string(other), `"deny"`) || string(user) != `{"permissions":{"allow":["Bash"]}}` {
		t.Fatalf("saved to the wrong file:\nother %s\nuser %s", other, user)
	}
}

func TestSwitchingToInvalidFileKeepsCurrentOne(t *testing.T) {
	f := newFixture(t, `{"permissions":{"allow":["Bash"]}}`, "Bash")
	os.WriteFile(f.otherPath, []byte(`{not json`), 0o644)
	m := f.model(t)

	m = press(m, "f", "down", "enter")
	if m.config.SettingsPath != f.settingsPath || m.states["Bash"].Permission != settings.Allow {
		t.Fatalf("switched to a broken file: %s", m.config.SettingsPath)
	}
	if !strings.Contains(m.status, f.otherPath) || !strings.Contains(m.status, "not valid JSON") {
		t.Fatalf("status should explain the failure: %q", m.status)
	}
}

func TestSwitchingWithUnsavedChangesNeedsConfirmation(t *testing.T) {
	f := newFixture(t, `{}`, "Bash")
	m := f.model(t)
	m = press(m, "a", "f", "down", "enter")

	if m.config.SettingsPath != f.settingsPath || !strings.Contains(m.status, "Unsaved changes") {
		t.Fatalf("switched without confirmation: %q", m.status)
	}
	m = press(m, "enter")
	if m.config.SettingsPath != f.otherPath || m.dirty() {
		t.Fatalf("second enter should switch and drop the edit: %s", m.config.SettingsPath)
	}
}

func TestEscapeClosesFilePickerWithoutSwitching(t *testing.T) {
	f := newFixture(t, `{}`, "Bash")
	m := press(f.model(t), "f", "down", "esc")

	if m.picking || m.config.SettingsPath != f.settingsPath {
		t.Fatal("escape should close the picker and keep the file")
	}
}

func TestFilePickerNeedsAnotherFile(t *testing.T) {
	f := newFixture(t, `{}`, "Bash")
	files := []settings.File{{Label: "user", Path: f.settingsPath}}
	m, _ := New(Config{SettingsPath: f.settingsPath, SettingsFiles: files, SnapshotPath: f.snapshotPath, DocsURL: f.docsURL})

	m = press(m, "f")
	if m.picking || m.status != "No other settings files found." {
		t.Fatalf("got picking=%v status %q", m.picking, m.status)
	}
}

func TestViewShowsActiveFileAndPicker(t *testing.T) {
	f := newFixture(t, `{}`, "Bash")
	m := f.model(t)

	if title := ansi.Strip(m.titleLine()); !strings.Contains(title, "user · "+f.settingsPath) {
		t.Fatalf("title missing active file: %q", title)
	}
	wide, _ := press(m, "f").Update(tea.WindowSizeMsg{Width: 300, Height: 30})
	content := ansi.Strip(wide.(Model).View().Content)
	for _, want := range []string{"local", f.otherPath, "● active", "(new)", "enter"} {
		if !strings.Contains(content, want) {
			t.Errorf("picker missing %q:\n%s", want, content)
		}
	}
}
