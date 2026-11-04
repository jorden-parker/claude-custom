package launchd

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/history"
)

var agent = Agent{
	Label:   "local.ollama",
	Program: "/opt/homebrew/bin/ollama",
	LogPath: "/Users/me/Library/Logs/ollama.log",
	Env:     map[string]string{"OLLAMA_KEEP_ALIVE": "-1", "OLLAMA_FLASH_ATTENTION": "1"},
}

func TestRenderRoundTripsTheEnvironment(t *testing.T) {
	env, err := ReadEnv(Render(agent))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(env, agent.Env) {
		t.Fatalf("got %v, want %v", env, agent.Env)
	}
}

func TestRenderRunsOllamaServeUnderTheLabel(t *testing.T) {
	rendered := string(Render(agent))
	for _, want := range []string{
		"<key>Label</key><string>local.ollama</string>",
		"<array><string>/opt/homebrew/bin/ollama</string><string>serve</string></array>",
		"<key>RunAtLoad</key><true/>",
		"<key>StandardErrorPath</key><string>/Users/me/Library/Logs/ollama.log</string>",
	} {
		if !strings.Contains(rendered, want) {
			t.Errorf("missing %q in\n%s", want, rendered)
		}
	}
}

func TestRenderSortsVariablesSoSavesAreStable(t *testing.T) {
	rendered := string(Render(agent))
	if strings.Index(rendered, "OLLAMA_FLASH_ATTENTION") > strings.Index(rendered, "OLLAMA_KEEP_ALIVE") {
		t.Fatalf("variables not sorted:\n%s", rendered)
	}
}

func TestRenderEscapesValues(t *testing.T) {
	escaped := Agent{Label: "a", Program: "/bin/ollama", Env: map[string]string{"OLLAMA_ORIGINS": "<a>&b"}}
	env, err := ReadEnv(Render(escaped))
	if err != nil {
		t.Fatal(err)
	}
	if env["OLLAMA_ORIGINS"] != "<a>&b" {
		t.Fatalf("got %q", env["OLLAMA_ORIGINS"])
	}
}

func TestReadEnvWithoutEnvironmentIsEmpty(t *testing.T) {
	env, err := ReadEnv([]byte(`<plist version="1.0"><dict><key>Label</key><string>x</string></dict></plist>`))
	if err != nil || len(env) != 0 {
		t.Fatalf("got %v, %v", env, err)
	}
}

func TestReadEnvRejectsBrokenXML(t *testing.T) {
	if _, err := ReadEnv([]byte(`<plist><dict><key>EnvironmentVariables</key><dict><key>A</key>`)); err == nil {
		t.Fatal("expected an error")
	}
}

func TestLoadMissingFileReportsAbsent(t *testing.T) {
	env, found, err := Load(filepath.Join(t.TempDir(), "missing.plist"))
	if err != nil || found || len(env) != 0 {
		t.Fatalf("got %v, %v, %v", env, found, err)
	}
}

func TestSaveThenLoad(t *testing.T) {
	path := filepath.Join(t.TempDir(), "LaunchAgents", "local.ollama.plist")
	if err := Save(path, agent); err != nil {
		t.Fatal(err)
	}
	env, found, err := Load(path)
	if err != nil || !found || !reflect.DeepEqual(env, agent.Env) {
		t.Fatalf("got %v, %v, %v", env, found, err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0o644 {
		t.Fatalf("mode %v, %v", info.Mode().Perm(), err)
	}
}

func isolateLaunchHistory(t *testing.T) string {
	t.Helper()
	t.Setenv("CLAUDE_CONSOLE_STATE_DIR", t.TempDir())
	t.Setenv("CLAUDE_CUSTOM_HISTORY", "")
	return history.Dir()
}

func TestSaveRecordsNewPlistWithoutBefore(t *testing.T) {
	dir := isolateLaunchHistory(t)
	path := filepath.Join(t.TempDir(), "local.ollama.plist")

	if err := Save(path, agent); err != nil {
		t.Fatal(err)
	}

	entries, err := history.List(dir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("entries = %v, %v, want one", entries, err)
	}
	entry := entries[0]
	if entry.Kind != "launch-agent" || entry.Path != path || entry.Before != nil {
		t.Fatalf("entry = %+v", entry)
	}
	if got := readPlist(t, filepath.Join(dir, entry.After)); got != string(Render(agent)) {
		t.Errorf("after bytes differ from Render")
	}
}

func TestSaveRecordsPreviousPlistBeforeReplacing(t *testing.T) {
	dir := isolateLaunchHistory(t)
	path := filepath.Join(t.TempDir(), "local.ollama.plist")
	if err := Save(path, agent); err != nil {
		t.Fatal(err)
	}
	previous := readPlist(t, path)
	changed := agent
	changed.Env = map[string]string{"OLLAMA_KEEP_ALIVE": "10m"}

	if err := Save(path, changed); err != nil {
		t.Fatal(err)
	}

	entries, err := history.List(dir)
	if err != nil || len(entries) != 2 || entries[0].Before == nil {
		t.Fatalf("entries = %v, %v, want two with a before", entries, err)
	}
	if got := readPlist(t, filepath.Join(dir, *entries[0].Before)); got != previous {
		t.Errorf("before bytes differ from the previous plist")
	}
}

func TestSaveLeavesPlistMissingWhenRecordingFails(t *testing.T) {
	dir := isolateLaunchHistory(t)
	if err := os.WriteFile(dir, []byte("a file, not a folder"), 0o600); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "local.ollama.plist")

	if err := Save(path, agent); err == nil {
		t.Fatal("Save succeeded though recording failed")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("plist exists after failed record: %v", err)
	}
}

func readPlist(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
