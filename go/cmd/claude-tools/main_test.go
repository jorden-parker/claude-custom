package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/teststate"
)

func TestMain(m *testing.M) {
	os.Exit(teststate.Run(m.Run))
}

func TestConflictingTarget(t *testing.T) {
	tests := []struct {
		name        string
		settingsSet bool
		scopeArg    string
		want        bool
	}{
		{name: "neither given", settingsSet: false, scopeArg: "", want: false},
		{name: "scope only", settingsSet: false, scopeArg: "user", want: false},
		{name: "settings only", settingsSet: true, scopeArg: "", want: false},
		{name: "settings and scope", settingsSet: true, scopeArg: "user", want: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := conflictingTarget(tt.settingsSet, tt.scopeArg); got != tt.want {
				t.Errorf("conflictingTarget(%v, %q) = %v, want %v", tt.settingsSet, tt.scopeArg, got, tt.want)
			}
		})
	}
}

func TestLoadCatalogReportsFetchErrorWhenNoCatalogExists(t *testing.T) {
	t.Setenv("CLAUDE_TOOLS_DOCS_URL", "http://127.0.0.1:9/tools-reference.md")
	path := filepath.Join(t.TempDir(), "tools.json")

	_, err := loadCatalog(path)

	if err == nil || !strings.HasPrefix(err.Error(), "no tool catalog yet; open claude-tools once and sync: ") {
		t.Fatalf("loadCatalog error = %v, want the no-catalog message with the fetch error", err)
	}
}
