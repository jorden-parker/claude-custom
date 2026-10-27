package launchd

import (
	"slices"
	"testing"
)

func TestReloadCommandBootsOutThenBootstrapsTheAgent(t *testing.T) {
	cmd := ReloadCommand("/Users/me/Library/LaunchAgents/local.ollama.plist", 501)
	want := []string{"gui/501/local.ollama", "gui/501", "/Users/me/Library/LaunchAgents/local.ollama.plist"}
	if cmd.Args[0] != "sh" || !slices.Equal(cmd.Args[len(cmd.Args)-3:], want) {
		t.Fatalf("got %v", cmd.Args)
	}
}

func TestServiceTargetNamesTheUserDomain(t *testing.T) {
	if got := ServiceTarget(501, "sh.brew.ollama"); got != "gui/501/sh.brew.ollama" {
		t.Fatalf("got %q", got)
	}
}

func TestBrewServiceIsFoundUnderEitherHomebrewLabel(t *testing.T) {
	for _, loaded := range BrewLabels {
		isLoaded := func(label string) bool { return label == loaded }
		if !anyLoaded(BrewLabels, isLoaded) {
			t.Fatalf("%s loaded but not found", loaded)
		}
	}
	if !slices.Contains(BrewLabels, "sh.brew.ollama") || !slices.Contains(BrewLabels, "homebrew.mxcl.ollama") {
		t.Fatalf("got %v", BrewLabels)
	}
}

func TestBrewServiceIsAbsentWhenNoLabelIsLoaded(t *testing.T) {
	if anyLoaded(BrewLabels, func(string) bool { return false }) {
		t.Fatal("found a brew service that is not loaded")
	}
}
