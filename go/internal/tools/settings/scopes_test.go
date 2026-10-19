package settings

import (
	"reflect"
	"testing"
)

func TestFilesListsUserProjectAndLocalScopes(t *testing.T) {
	got := Files("/home/me", "/work/repo", "/home/me/.claude/settings.json")

	want := []File{
		{Label: "user", Path: "/home/me/.claude/settings.json"},
		{Label: "project", Path: "/work/repo/.claude/settings.json"},
		{Label: "local", Path: "/work/repo/.claude/settings.local.json"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v", got)
	}
}

func TestFilesSkipsProjectScopeThatIsTheUserFile(t *testing.T) {
	got := Files("/home/me", "/home/me", "/home/me/.claude/settings.json")

	want := []File{
		{Label: "user", Path: "/home/me/.claude/settings.json"},
		{Label: "local", Path: "/home/me/.claude/settings.local.json"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v", got)
	}
}

func TestFilesListsCustomPathFirst(t *testing.T) {
	got := Files("/home/me", "/work/repo", "/work/repo/ollama/../ollama/settings.27b.json")

	if got[0] != (File{Label: "custom", Path: "/work/repo/ollama/settings.27b.json"}) || len(got) != 4 {
		t.Fatalf("got %+v", got)
	}
}

func TestFilesDoesNotDuplicateCustomPathMatchingAScope(t *testing.T) {
	got := Files("/home/me", "/work/repo", "/work/repo/.claude/settings.local.json")

	if len(got) != 3 || got[2].Label != "local" {
		t.Fatalf("got %+v", got)
	}
}

func TestResolvePathMapsScopeLabelsToPaths(t *testing.T) {
	cases := map[string]string{
		"user":    "/home/me/.claude/settings.json",
		"project": "/work/repo/.claude/settings.json",
		"local":   "/work/repo/.claude/settings.local.json",
	}
	for label, want := range cases {
		if got := ResolvePath("/home/me", "/work/repo", label); got != want {
			t.Errorf("%s: got %s, want %s", label, got, want)
		}
	}
}

func TestResolvePathKeepsAnythingElseAsAPath(t *testing.T) {
	if got := ResolvePath("/home/me", "/work/repo", "ollama/settings.27b.json"); got != "ollama/settings.27b.json" {
		t.Fatalf("got %s", got)
	}
}
