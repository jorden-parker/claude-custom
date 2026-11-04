package snapshot

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

var recommended = map[string]string{"cache-type-k": "q8_0", variables.ModelsMax: "2"}

func paths(t *testing.T) (string, string) {
	dir := t.TempDir()
	return filepath.Join(dir, "local.llama-server.plist"), filepath.Join(dir, "server.local.ini")
}

func find(t *testing.T, state Snapshot, name string) Setting {
	t.Helper()
	at := slices.IndexFunc(state.Variables, func(setting Setting) bool { return setting.Name == name })
	if at < 0 {
		t.Fatalf("%s missing from %+v", name, state.Variables)
	}
	return state.Variables[at]
}

func TestBuildWithoutAgentOrOverridesShowsTheRecommendedValues(t *testing.T) {
	plist, overrides := paths(t)
	state, err := Build(plist, overrides, recommended, nil)
	if err != nil {
		t.Fatal(err)
	}
	if state.Exists || state.Path != plist || state.Overrides != overrides || state.Conflicts == nil {
		t.Fatalf("state %+v", state)
	}
	setting := find(t, state, "cache-type-k")
	if setting.Current != "q8_0" || setting.Set || setting.Recommended != "q8_0" || setting.Summary == "" {
		t.Fatalf("setting %+v", setting)
	}
}

func TestBuildMarksOverriddenKeys(t *testing.T) {
	plist, overrides := paths(t)
	t.Setenv("CLAUDE_CONSOLE_STATE_DIR", t.TempDir())
	if err := variables.Save(overrides, map[string]string{variables.ModelsMax: "3"}); err != nil {
		t.Fatal(err)
	}
	if _, err := launchd.Save(plist, launchd.Server{Program: "/bin/llama-server", ModelsMax: "3"}.Agent()); err != nil {
		t.Fatal(err)
	}
	state, err := Build(plist, overrides, recommended, []string{"brew services also runs llama.cpp"})
	if err != nil {
		t.Fatal(err)
	}
	setting := find(t, state, variables.ModelsMax)
	if !state.Exists || setting.Current != "3" || !setting.Set || setting.Recommended != "2" || len(state.Conflicts) != 1 {
		t.Fatalf("state %+v, setting %+v", state, setting)
	}
}

func TestBuildReportsABrokenOverridesFile(t *testing.T) {
	plist, overrides := paths(t)
	if err := os.WriteFile(overrides, []byte("[*]\nbroken\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Build(plist, overrides, recommended, nil); err == nil {
		t.Fatal("expected an error")
	}
}

func TestJSONKeysStayStable(t *testing.T) {
	plist, overrides := paths(t)
	state, err := Build(plist, overrides, recommended, nil)
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{`"path"`, `"exists"`, `"overrides"`, `"variables"`, `"conflicts"`, `"name"`, `"summary"`, `"current"`, `"set"`, `"recommended"`} {
		if !strings.Contains(string(data), key) {
			t.Errorf("missing %s in %s", key, data)
		}
	}
}
