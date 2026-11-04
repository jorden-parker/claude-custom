package variables

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
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

func TestWithServerEnvAddsAndOverridesOnlyServerEnvNames(t *testing.T) {
	current := map[string]string{"OLLAMA_KEEP_ALIVE": "5m", "OLLAMA_DEBUG": "1", "OLLAMA_FLASH_ATTENTION": "1"}
	serverEnv := map[string]string{"OLLAMA_KEEP_ALIVE": "30m", "OLLAMA_FLASH_ATTENTION": "1", "OLLAMA_MAX_LOADED_MODELS": "2"}
	env, changed := WithServerEnv(current, serverEnv)
	want := map[string]string{"OLLAMA_KEEP_ALIVE": "30m", "OLLAMA_DEBUG": "1", "OLLAMA_FLASH_ATTENTION": "1", "OLLAMA_MAX_LOADED_MODELS": "2"}
	if !reflect.DeepEqual(env, want) {
		t.Fatalf("env %v", env)
	}
	if !reflect.DeepEqual(changed, []string{"OLLAMA_KEEP_ALIVE", "OLLAMA_MAX_LOADED_MODELS"}) {
		t.Fatalf("changed %v", changed)
	}
	if current["OLLAMA_KEEP_ALIVE"] != "5m" {
		t.Fatal("current was modified")
	}
}

func TestWithServerEnvStartsFromNoAgent(t *testing.T) {
	env, changed := WithServerEnv(nil, map[string]string{"OLLAMA_KEEP_ALIVE": "30m"})
	if env["OLLAMA_KEEP_ALIVE"] != "30m" || len(changed) != 1 {
		t.Fatalf("got %v, %v", env, changed)
	}
}

func TestParseAssignmentSplitsNameAndValue(t *testing.T) {
	name, value, err := ParseAssignment("OLLAMA_KEEP_ALIVE=30m")
	if err != nil || name != "OLLAMA_KEEP_ALIVE" || value != "30m" {
		t.Fatalf("got %q, %q, %v", name, value, err)
	}
}

func TestParseAssignmentRejects(t *testing.T) {
	longValue := "OLLAMA_KEEP_ALIVE=" + strings.Repeat("x", 257)
	cases := map[string]string{
		"no equals sign":   "OLLAMA_KEEP_ALIVE",
		"unknown name":     "OLLAMA_NOPE=1",
		"newline in value": "OLLAMA_KEEP_ALIVE=1\n2",
		"nul in value":     "OLLAMA_KEEP_ALIVE=1\x002",
		"value too long":   longValue,
	}
	for label, text := range cases {
		if _, _, err := ParseAssignment(text); err == nil {
			t.Fatalf("%s: expected an error for %q", label, text)
		}
	}
}

func TestParseAssignmentAcceptsValueAtLimit(t *testing.T) {
	text := "OLLAMA_KEEP_ALIVE=" + strings.Repeat("x", 256)
	if _, _, err := ParseAssignment(text); err != nil {
		t.Fatalf("got %v", err)
	}
}
