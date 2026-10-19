package catalog

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func readFixture(t *testing.T) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", "tools-reference.md"))
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func names(tools []Tool) []string {
	var result []string
	for _, tool := range tools {
		result = append(result, tool.Name)
	}
	return result
}

func TestParseReadsOnlyTheToolsTable(t *testing.T) {
	tools, err := Parse(readFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	got := strings.Join(names(tools), ",")
	if got != "Agent,Bash,TodoWrite,WebSearch" {
		t.Fatalf("got %s", got)
	}
}

func TestParseDropsRemovedTools(t *testing.T) {
	tools, _ := Parse(readFixture(t))
	for _, tool := range tools {
		if tool.Name == "TaskOutput" {
			t.Fatal("TaskOutput is marked removed and must be dropped")
		}
	}
}

func TestParseDropsDeprecatedTools(t *testing.T) {
	doc := toolsTableHeader + "| `Old` | Deprecated. Use `New` instead | No |\n| `New` | Does things | Yes |\n"
	tools, _ := Parse([]byte(doc))
	if got := strings.Join(names(tools), ","); got != "New" {
		t.Fatalf("got %s", got)
	}
}

func TestParseStripsMarkdownFromDescription(t *testing.T) {
	tools, _ := Parse(readFixture(t))
	bash := tools[1]
	if bash.Description != "Executes shell commands in your environment. See Bash tool behavior" {
		t.Fatalf("got %q", bash.Description)
	}
}

func TestParseReadsPermissionRequired(t *testing.T) {
	tools, _ := Parse(readFixture(t))
	if tools[0].PromptsByDefault || !tools[1].PromptsByDefault {
		t.Fatalf("Agent should not prompt, Bash should: %+v", tools[:2])
	}
}

func TestParseFailsWhenTableIsMissing(t *testing.T) {
	if _, err := Parse([]byte("# Tools reference\n\nnothing here\n")); err == nil {
		t.Fatal("expected an error")
	}
}

func TestFetchParsesServedDocs(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write(readFixture(t))
	}))
	defer server.Close()

	tools, err := Fetch(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	if len(tools) != 4 {
		t.Fatalf("got %d tools", len(tools))
	}
}

func TestFetchFailsOnHTTPError(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	defer server.Close()

	if _, err := Fetch(server.URL); err == nil {
		t.Fatal("expected an error")
	}
}

func TestCacheRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "tools.json")
	synced := time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC)
	want := Snapshot{Source: "https://example.test", SyncedAt: synced, Tools: []Tool{{Name: "Bash", PromptsByDefault: true}}}

	if err := SaveSnapshot(path, want); err != nil {
		t.Fatal(err)
	}
	got, err := LoadSnapshot(path)
	if err != nil {
		t.Fatal(err)
	}
	if got.Source != want.Source || !got.SyncedAt.Equal(synced) || got.Tools[0] != want.Tools[0] {
		t.Fatalf("got %+v", got)
	}
}

func TestDiffReportsAddedAndDropped(t *testing.T) {
	before := []Tool{{Name: "Bash"}, {Name: "TaskOutput"}}
	after := []Tool{{Name: "Bash"}, {Name: "Workflow"}}

	added, dropped := Diff(before, after)
	if strings.Join(added, ",") != "Workflow" || strings.Join(dropped, ",") != "TaskOutput" {
		t.Fatalf("added %v dropped %v", added, dropped)
	}
}

const toolsTableHeader = "| Tool | Description | Permission required |\n| :- | :- | :- |\n"
