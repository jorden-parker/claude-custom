package snapshot

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
)

var recommended = map[string]string{"OLLAMA_KEEP_ALIVE": "30m", "OLLAMA_MAX_LOADED_MODELS": "2"}

func writePlist(t *testing.T, env map[string]string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "local.ollama.plist")
	agent := launchd.Agent{Label: launchd.Label, Program: "/opt/homebrew/bin/ollama", LogPath: "/tmp/ollama.log", Env: env}
	if err := launchd.Save(path, agent); err != nil {
		t.Fatal(err)
	}
	return path
}

func variableNamed(t *testing.T, snap Snapshot, name string) Variable {
	t.Helper()
	for _, variable := range snap.Variables {
		if variable.Name == name {
			return variable
		}
	}
	t.Fatalf("no variable %s in %v", name, snap.Variables)
	return Variable{}
}

func TestBuildReadsCurrentValuesFromThePlist(t *testing.T) {
	path := writePlist(t, map[string]string{"OLLAMA_KEEP_ALIVE": "5m"})
	snap, err := Build(path, recommended, nil)
	if err != nil || !snap.Exists || snap.Path != path {
		t.Fatalf("got %+v, %v", snap, err)
	}
	keepAlive := variableNamed(t, snap, "OLLAMA_KEEP_ALIVE")
	want := Variable{Name: "OLLAMA_KEEP_ALIVE", Summary: "how long an idle model stays loaded (-1 = forever)", Current: "5m", Set: true, Recommended: "30m"}
	if keepAlive != want {
		t.Fatalf("got %+v, want %+v", keepAlive, want)
	}
	maxLoaded := variableNamed(t, snap, "OLLAMA_MAX_LOADED_MODELS")
	if maxLoaded.Set || maxLoaded.Current != "" || maxLoaded.Recommended != "2" {
		t.Fatalf("got %+v", maxLoaded)
	}
}

func TestBuildListsVariablesInTheTUIOrder(t *testing.T) {
	path := writePlist(t, map[string]string{"OLLAMA_CUSTOM": "x"})
	snap, err := Build(path, recommended, nil)
	if err != nil {
		t.Fatal(err)
	}
	names := make([]string, 0, len(snap.Variables))
	for _, variable := range snap.Variables {
		names = append(names, variable.Name)
	}
	last := names[len(names)-1]
	if names[0] != "OLLAMA_KEEP_ALIVE" || last != "OLLAMA_CUSTOM" || len(names) != 12 {
		t.Fatalf("got %v", names)
	}
}

func TestBuildWithMissingPlistMarksEverythingUnset(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing.plist")
	snap, err := Build(path, recommended, nil)
	if err != nil || snap.Exists {
		t.Fatalf("got %+v, %v", snap, err)
	}
	for _, variable := range snap.Variables {
		if variable.Set {
			t.Fatalf("%s is set without a plist", variable.Name)
		}
	}
	if variableNamed(t, snap, "OLLAMA_KEEP_ALIVE").Recommended != "30m" {
		t.Fatal("recommended values should still show")
	}
}

func TestBuildPassesConflictsThrough(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing.plist")
	snap, err := Build(path, recommended, []string{"brew services also runs ollama"})
	if err != nil || !reflect.DeepEqual(snap.Conflicts, []string{"brew services also runs ollama"}) {
		t.Fatalf("got %+v, %v", snap.Conflicts, err)
	}
}

func TestBuildUsesAnEmptyListWithoutConflicts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing.plist")
	snap, err := Build(path, recommended, nil)
	if err != nil || snap.Conflicts == nil || len(snap.Conflicts) != 0 {
		t.Fatalf("got %#v, %v", snap.Conflicts, err)
	}
}

func TestBuildReportsAPlistThatIsNotValid(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bad.plist")
	if err := os.WriteFile(path, []byte("<plist><dict><key>EnvironmentVariables"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Build(path, recommended, nil); err == nil {
		t.Fatal("expected an error")
	}
}
