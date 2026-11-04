package launchd

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/history"
)

var server = Server{
	Program:   "/opt/homebrew/bin/llama-server",
	Presets:   "/Users/me/.claude-ollama/presets/models.ini",
	ModelsMax: "2",
	LogFile:   "/Users/me/.claude-ollama/logs/llama-server.log",
	LogPath:   "/Users/me/.claude-ollama/logs/llama-server.stdout.log",
}

var agent = server.Agent()

func TestServerAgentRunsTheRouterOnItsOwnPort(t *testing.T) {
	want := []string{
		"/opt/homebrew/bin/llama-server",
		"--models-preset", "/Users/me/.claude-ollama/presets/models.ini",
		"--models-max", "2",
		"--host", "127.0.0.1",
		"--port", "11435",
		"--log-file", "/Users/me/.claude-ollama/logs/llama-server.log",
		"--metrics",
	}
	if agent.Label != "local.llama-server" || !slices.Equal(agent.Arguments, want) {
		t.Fatalf("got %s %v", agent.Label, agent.Arguments)
	}
}

func TestRenderRoundTripsTheArguments(t *testing.T) {
	arguments, err := ReadArguments(Render(agent))
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(arguments, agent.Arguments) {
		t.Fatalf("got %v, want %v", arguments, agent.Arguments)
	}
}

func TestRenderPutsEachArgumentOnItsOwnLine(t *testing.T) {
	rendered := string(Render(agent))
	for _, want := range []string{
		"<key>Label</key><string>local.llama-server</string>",
		"\n    <string>--models-max</string>\n    <string>2</string>\n",
		"<key>RunAtLoad</key><true/>",
		"<key>KeepAlive</key><true/>",
		"<key>StandardOutPath</key><string>/Users/me/.claude-ollama/logs/llama-server.stdout.log</string>",
		"<key>StandardErrorPath</key><string>/Users/me/.claude-ollama/logs/llama-server.stdout.log</string>",
	} {
		if !strings.Contains(rendered, want) {
			t.Errorf("missing %q in\n%s", want, rendered)
		}
	}
	if strings.Contains(rendered, "EnvironmentVariables") {
		t.Errorf("the router needs no environment:\n%s", rendered)
	}
}

func TestRenderEscapesArguments(t *testing.T) {
	escaped := Agent{Label: "a", Arguments: []string{"/bin/llama-server", "<a>&b"}}
	arguments, err := ReadArguments(Render(escaped))
	if err != nil {
		t.Fatal(err)
	}
	if arguments[1] != "<a>&b" {
		t.Fatalf("got %q", arguments[1])
	}
}

func TestReadArgumentsWithoutProgramArgumentsIsEmpty(t *testing.T) {
	arguments, err := ReadArguments([]byte(`<plist version="1.0"><dict><key>Label</key><string>x</string></dict></plist>`))
	if err != nil || len(arguments) != 0 {
		t.Fatalf("got %v, %v", arguments, err)
	}
}

func TestReadArgumentsRejectsBrokenXML(t *testing.T) {
	if _, err := ReadArguments([]byte(`<plist><dict><key>ProgramArguments</key><array><string>a</string>`)); err == nil {
		t.Fatal("expected an error")
	}
}

func TestModelsMaxReadsTheValueAfterTheFlag(t *testing.T) {
	path := filepath.Join(t.TempDir(), "local.llama-server.plist")
	if _, err := Save(path, agent); err != nil {
		t.Fatal(err)
	}
	value, found, err := ModelsMax(path)
	if err != nil || !found || value != "2" {
		t.Fatalf("got %q, %v, %v", value, found, err)
	}
}

func TestModelsMaxOfAMissingPlistIsAbsent(t *testing.T) {
	value, found, err := ModelsMax(filepath.Join(t.TempDir(), "missing.plist"))
	if err != nil || found || value != "" {
		t.Fatalf("got %q, %v, %v", value, found, err)
	}
}

func TestLoadMissingFileReportsAbsent(t *testing.T) {
	data, found, err := Load(filepath.Join(t.TempDir(), "missing.plist"))
	if err != nil || found || len(data) != 0 {
		t.Fatalf("got %q, %v, %v", data, found, err)
	}
}

func TestSaveThenLoad(t *testing.T) {
	path := filepath.Join(t.TempDir(), "LaunchAgents", "local.llama-server.plist")
	written, err := Save(path, agent)
	if err != nil || !written {
		t.Fatalf("written %v, %v", written, err)
	}
	data, found, err := Load(path)
	if err != nil || !found || string(data) != string(Render(agent)) {
		t.Fatalf("got %v, %v", found, err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0o644 {
		t.Fatalf("mode %v, %v", info.Mode().Perm(), err)
	}
}

func TestSaveLeavesAnIdenticalPlistAlone(t *testing.T) {
	dir := isolateLaunchHistory(t)
	path := filepath.Join(t.TempDir(), "local.llama-server.plist")
	if _, err := Save(path, agent); err != nil {
		t.Fatal(err)
	}
	written, err := Save(path, agent)
	if err != nil || written {
		t.Fatalf("written %v, %v", written, err)
	}
	if entries, _ := history.List(dir); len(entries) != 1 {
		t.Fatalf("entries = %v, want one", entries)
	}
}

func TestDefaultPathFollowsTheEnvironment(t *testing.T) {
	t.Setenv("LLAMA_SERVER_PLIST", "/tmp/elsewhere.plist")
	path, err := DefaultPath()
	if err != nil || path != "/tmp/elsewhere.plist" {
		t.Fatalf("got %q, %v", path, err)
	}
}

func TestDefaultPathIsTheUserLaunchAgent(t *testing.T) {
	t.Setenv("LLAMA_SERVER_PLIST", "")
	t.Setenv("HOME", "/Users/me")
	path, err := DefaultPath()
	if err != nil || path != "/Users/me/Library/LaunchAgents/local.llama-server.plist" {
		t.Fatalf("got %q, %v", path, err)
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
	path := filepath.Join(t.TempDir(), "local.llama-server.plist")

	if _, err := Save(path, agent); err != nil {
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
	path := filepath.Join(t.TempDir(), "local.llama-server.plist")
	if _, err := Save(path, agent); err != nil {
		t.Fatal(err)
	}
	previous := readPlist(t, path)
	changed := server
	changed.ModelsMax = "3"

	if _, err := Save(path, changed.Agent()); err != nil {
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
	path := filepath.Join(t.TempDir(), "local.llama-server.plist")

	if _, err := Save(path, agent); err == nil {
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
