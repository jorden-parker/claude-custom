package variables

import (
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/history"
)

const serverINI = `[*]
n-gpu-layers = 99
cache-type-k = q8_0
jinja = true

[router]
models-max = 2
`

func writeFile(t *testing.T, name, text string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestEveryKnownSettingHasASummary(t *testing.T) {
	for _, setting := range Known {
		if setting.Summary == "" {
			t.Errorf("%s has no summary", setting.Name)
		}
	}
	if Summary(ModelsMax) == "" || Summary("cache-type-k") == "" {
		t.Fatal("models-max and cache-type-k must be known")
	}
}

func TestLoadReadsTheSharedKeysAndTheRouterFlag(t *testing.T) {
	values, err := Load(writeFile(t, "server.ini", serverINI))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"n-gpu-layers": "99", "cache-type-k": "q8_0", "jinja": "true", ModelsMax: "2"}
	if !reflect.DeepEqual(values, want) {
		t.Fatalf("got %v", values)
	}
}

func TestLoadIgnoresOtherSectionsAndComments(t *testing.T) {
	values, err := Load(writeFile(t, "models.ini", "; note\n[*]\nparallel = 1\n\n[qwen]\nctx-size = 4096\n[router]\nother = 3\n"))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(values, map[string]string{"parallel": "1"}) {
		t.Fatalf("got %v", values)
	}
}

func TestLoadOfAMissingFileIsEmpty(t *testing.T) {
	values, err := Load(filepath.Join(t.TempDir(), "missing.ini"))
	if err != nil || len(values) != 0 {
		t.Fatalf("got %v, %v", values, err)
	}
}

func TestLoadRejectsALineWithoutAnEquals(t *testing.T) {
	if _, err := Load(writeFile(t, "bad.ini", "[*]\nflash-attn\n")); err == nil || !strings.Contains(err.Error(), "line 2") {
		t.Fatalf("got %v", err)
	}
}

func TestEffectiveLaysOverridesOverTheRecommendedValues(t *testing.T) {
	got := Effective(map[string]string{"parallel": "1", ModelsMax: "2"}, map[string]string{ModelsMax: "3"})
	if !reflect.DeepEqual(got, map[string]string{"parallel": "1", ModelsMax: "3"}) {
		t.Fatalf("got %v", got)
	}
}

func TestOverridesKeepOnlyWhatDiffersFromTheRecommendedValues(t *testing.T) {
	got := Overrides(map[string]string{"parallel": "1", ModelsMax: "2"}, map[string]string{"parallel": "1", ModelsMax: "3", "prio": "1"})
	if !reflect.DeepEqual(got, map[string]string{ModelsMax: "3", "prio": "1"}) {
		t.Fatalf("got %v", got)
	}
}

func TestRenderSortsTheSharedKeysAndPutsTheRouterFlagLast(t *testing.T) {
	got := string(Render(map[string]string{ModelsMax: "3", "prio": "1", "cache-reuse": "512"}))
	want := "[*]\ncache-reuse = 512\nprio = 1\n\n[router]\nmodels-max = 3\n"
	if got != want {
		t.Fatalf("got %q", got)
	}
}

func TestRenderOfNoOverridesIsEmpty(t *testing.T) {
	if got := Render(map[string]string{}); len(got) != 0 {
		t.Fatalf("got %q", got)
	}
}

func TestSaveThenLoadRoundTrips(t *testing.T) {
	t.Setenv("CLAUDE_CONSOLE_STATE_DIR", t.TempDir())
	path := filepath.Join(t.TempDir(), "presets", "server.local.ini")
	values := map[string]string{ModelsMax: "3", "cache-type-k": "f16"}
	if err := Save(path, values); err != nil {
		t.Fatal(err)
	}
	loaded, err := Load(path)
	if err != nil || !reflect.DeepEqual(loaded, values) {
		t.Fatalf("got %v, %v", loaded, err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v, %v", info.Mode().Perm(), err)
	}
}

func TestSaveRecordsTheChange(t *testing.T) {
	t.Setenv("CLAUDE_CONSOLE_STATE_DIR", t.TempDir())
	t.Setenv("CLAUDE_CUSTOM_HISTORY", "")
	path := filepath.Join(t.TempDir(), "server.local.ini")
	if err := Save(path, map[string]string{"prio": "1"}); err != nil {
		t.Fatal(err)
	}
	entries, err := history.List(history.Dir())
	if err != nil || len(entries) != 1 || entries[0].Kind != "server-settings" {
		t.Fatalf("entries = %v, %v", entries, err)
	}
}

func TestSaveWritesNothingWhenTheFileAlreadyMatches(t *testing.T) {
	t.Setenv("CLAUDE_CONSOLE_STATE_DIR", t.TempDir())
	t.Setenv("CLAUDE_CUSTOM_HISTORY", "")
	missing := filepath.Join(t.TempDir(), "server.local.ini")
	if err := Save(missing, map[string]string{}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(missing); !os.IsNotExist(err) {
		t.Fatalf("no overrides wrote a file: %v", err)
	}
	if entries, _ := history.List(history.Dir()); len(entries) != 0 {
		t.Fatalf("entries = %v", entries)
	}
}

func TestParseAssignmentAcceptsAKnownKey(t *testing.T) {
	name, value, err := ParseAssignment("cache-type-k=f16")
	if err != nil || name != "cache-type-k" || value != "f16" {
		t.Fatalf("got %q %q %v", name, value, err)
	}
}

func TestParseAssignmentRejectsBadInput(t *testing.T) {
	for _, text := range []string{"cache-type-k", "OLLAMA_KEEP_ALIVE=1", "prio=", "prio=1\n2", "prio=" + strings.Repeat("9", 300), "prio=[x]"} {
		if _, _, err := ParseAssignment(text); err == nil {
			t.Errorf("%q: expected an error", text)
		}
	}
}

func TestNamesListsKnownKeysThenExtrasSorted(t *testing.T) {
	names := Names(map[string]string{"zz-extra": "1", "aa-extra": "2", "prio": "2"})
	if names[0] != Known[0].Name || !slices.Equal(names[len(names)-2:], []string{"aa-extra", "zz-extra"}) {
		t.Fatalf("got %v", names)
	}
}
