package profiles

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestLoadListsSettingsWhoseSizeIsInSizesJSON(t *testing.T) {
	got, err := Load("testdata")
	if err != nil {
		t.Fatal(err)
	}
	want := []Profile{
		{Size: "27b", Model: "qwen3.8-27b-cc", Base: "unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q4_K_XL.gguf"},
		{Size: "35b", Model: "qwen3.6-35b-cc", Base: "unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}

func TestLoadTakesTheBaseFromSizesJSON(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "settings.9b.json"), `{"model": "nine-cc"}`)
	writeFile(t, filepath.Join(dir, "sizes.json"), `{"9b": {"base": "org/repo/nine.gguf"}}`)
	got, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	want := []Profile{{Size: "9b", Model: "nine-cc", Base: "org/repo/nine.gguf"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}

func TestLoadSkipsSettingsWithoutSizesJSON(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "settings.9b.json"), `{"model": "nine-cc"}`)
	got, err := Load(dir)
	if err != nil || len(got) != 0 {
		t.Fatalf("got %v, %v", got, err)
	}
}

func TestLoadRejectsMalformedSizesJSON(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "settings.9b.json"), `{"model": "nine-cc"}`)
	writeFile(t, filepath.Join(dir, "sizes.json"), `{"9b":`)
	if _, err := Load(dir); err == nil {
		t.Fatal("expected an error for a malformed sizes.json")
	}
}

func TestLoadRejectsSettingsWithoutModel(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "settings.9b.json"), `{}`)
	writeFile(t, filepath.Join(dir, "sizes.json"), `{"9b": {"base": "org/repo/nine.gguf"}}`)
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
