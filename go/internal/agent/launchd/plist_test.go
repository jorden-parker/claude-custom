package launchd

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
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
