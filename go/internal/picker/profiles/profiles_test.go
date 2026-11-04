package profiles

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestLoadPairsSettingsWithModelfiles(t *testing.T) {
	got, err := Load("testdata")
	if err != nil {
		t.Fatal(err)
	}
	want := []Profile{
		{Size: "27b", Model: "qwen3.8-27b-cc", Base: "qwen3.8:27b-mlx"},
		{Size: "35b", Model: "qwen3.6-35b-cc", Base: "qwen3.6:35b-mlx"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}

func TestLoadRejectsSettingsWithoutModel(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "settings.9b.json"), []byte(`{}`), 0o644)
	os.WriteFile(filepath.Join(dir, "Modelfile.9b"), []byte("FROM base\n"), 0o644)
	if _, err := Load(dir); err == nil {
		t.Fatal("expected an error for settings without a model")
	}
}

func TestLoadEmptyDirReturnsNoProfiles(t *testing.T) {
	got, err := Load(t.TempDir())
	if err != nil || len(got) != 0 {
		t.Fatalf("got %v, %v", got, err)
	}
}
