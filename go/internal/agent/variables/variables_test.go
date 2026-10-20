package variables

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestParseServerEnvReadsAssignments(t *testing.T) {
	env, err := ParseServerEnv([]byte("OLLAMA_FLASH_ATTENTION=1\n\nOLLAMA_KEEP_ALIVE=30m\n"))
	want := map[string]string{"OLLAMA_FLASH_ATTENTION": "1", "OLLAMA_KEEP_ALIVE": "30m"}
	if err != nil || !reflect.DeepEqual(env, want) {
		t.Fatalf("got %v, %v", env, err)
	}
}

func TestParseServerEnvRejectsLinesWithoutAssignment(t *testing.T) {
	if _, err := ParseServerEnv([]byte("OLLAMA_DEBUG\n")); err == nil {
		t.Fatal("expected an error")
	}
}

func TestLoadServerEnvReadsTheRepoFile(t *testing.T) {
	env, err := LoadServerEnv(filepath.Join("..", "..", "..", "..", "ollama", "server.env"))
	if err != nil || env["OLLAMA_KV_CACHE_TYPE"] != "q8_0" {
		t.Fatalf("got %v, %v", env, err)
	}
}

func TestLoadServerEnvMissingFileIsEmpty(t *testing.T) {
	env, err := LoadServerEnv(filepath.Join(t.TempDir(), "server.env"))
	if err != nil || len(env) != 0 {
		t.Fatalf("got %v, %v", env, err)
	}
}

func TestLoadServerEnvReportsUnreadableFile(t *testing.T) {
	dir := t.TempDir()
	if err := os.Mkdir(filepath.Join(dir, "server.env"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadServerEnv(filepath.Join(dir, "server.env")); err == nil {
		t.Fatal("expected an error")
	}
}

func TestNamesPutsKnownVariablesFirstThenExtrasSorted(t *testing.T) {
	names := Names(map[string]string{"ZED": "1", "OLLAMA_KEEP_ALIVE": "-1"}, map[string]string{"ALPHA": "2"})
	if names[0] != Known[0].Name || names[len(names)-2] != "ALPHA" || names[len(names)-1] != "ZED" {
		t.Fatalf("got %v", names)
	}
	if len(names) != len(Known)+2 {
		t.Fatalf("got %d names, want %d", len(names), len(Known)+2)
	}
}

func TestSummaryOfUnknownVariableIsEmpty(t *testing.T) {
	if Summary("ZED") != "" || Summary("OLLAMA_KEEP_ALIVE") == "" {
		t.Fatal("wrong summaries")
	}
}
