package profiles

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadSideReadsBaseAndHaikuName(t *testing.T) {
	got, err := LoadSide("testdata")
	if err != nil {
		t.Fatal(err)
	}
	want := SideModel{Name: "qwen3-4b-cc", Base: "qwen3:4b", Modelfile: filepath.Join("testdata", "side.Modelfile")}
	if got != want {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}

func TestLoadSideWithoutModelfileReturnsNone(t *testing.T) {
	got, err := LoadSide(t.TempDir())
	if err != nil || got.Configured() {
		t.Fatalf("got %+v, %v", got, err)
	}
}

func TestLoadSideRejectsDisagreeingHaikuNames(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "side.Modelfile", "FROM qwen3:4b\n")
	writeFile(t, dir, "settings.27b.json", `{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"a-cc"}}`)
	writeFile(t, dir, "settings.35b.json", `{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"b-cc"}}`)
	if _, err := LoadSide(dir); err == nil {
		t.Fatal("expected an error for disagreeing Haiku models")
	}
}

func TestLoadSideRejectsMissingHaikuName(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "side.Modelfile", "FROM qwen3:4b\n")
	writeFile(t, dir, "settings.27b.json", `{"model":"big-cc"}`)
	if _, err := LoadSide(dir); err == nil {
		t.Fatal("expected an error when no settings name the Haiku model")
	}
}

func writeFile(t *testing.T, dir, name, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
