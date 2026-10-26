package report

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/tools/catalog"
)

var catalogTools = []catalog.Tool{
	{Name: "Bash", Description: "Runs shell commands", PromptsByDefault: true},
	{Name: "WebFetch", Description: "Fetches a URL", PromptsByDefault: true},
	{Name: "Read", Description: "Reads a file"},
}

func TestBuildReportsEachToolsState(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	data := `{"permissions":{"allow":["Bash"],"deny":["Bash","WebFetch"]}}`
	if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}

	built, err := Build(path, catalogTools)
	if err != nil {
		t.Fatal(err)
	}
	want := Report{
		Path: path,
		Tools: []Row{
			{Name: "Bash", Description: "Runs shell commands", PromptsByDefault: true, Permission: "allow", Disabled: true},
			{Name: "WebFetch", Description: "Fetches a URL", PromptsByDefault: true, Permission: "deny"},
			{Name: "Read", Description: "Reads a file", Permission: "default"},
		},
	}
	if !reflect.DeepEqual(built, want) {
		t.Fatalf("got %+v", built)
	}
}

func TestBuildTreatsMissingFileAsAllDefault(t *testing.T) {
	path := filepath.Join(t.TempDir(), "absent.json")

	built, err := Build(path, catalogTools)
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range built.Tools {
		if row.Permission != "default" || row.Disabled {
			t.Fatalf("got %+v", row)
		}
	}
	if len(built.Tools) != len(catalogTools) {
		t.Fatalf("got %d rows", len(built.Tools))
	}
}

func TestBuildRejectsInvalidJSON(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := os.WriteFile(path, []byte(`{`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Build(path, catalogTools); err == nil {
		t.Fatal("expected an error")
	}
}
