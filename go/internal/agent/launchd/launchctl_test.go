package launchd

import (
	"slices"
	"testing"
)

func TestReloadCommandBootsOutThenBootstrapsTheAgent(t *testing.T) {
	cmd := ReloadCommand("/Users/me/Library/LaunchAgents/local.llama-server.plist", 501)
	want := []string{"gui/501/local.llama-server", "gui/501", "/Users/me/Library/LaunchAgents/local.llama-server.plist"}
	if cmd.Args[0] != "sh" || !slices.Equal(cmd.Args[len(cmd.Args)-3:], want) {
		t.Fatalf("got %v", cmd.Args)
	}
}

func TestServiceTargetNamesTheUserDomain(t *testing.T) {
	if got := ServiceTarget(501, "homebrew.mxcl.llama.cpp"); got != "gui/501/homebrew.mxcl.llama.cpp" {
		t.Fatalf("got %q", got)
	}
}

func TestBrewServiceIsTheLlamaCppFormula(t *testing.T) {
	for _, loaded := range BrewLabels {
		isLoaded := func(label string) bool { return label == loaded }
		if !anyLoaded(BrewLabels, isLoaded) {
			t.Fatalf("%s loaded but not found", loaded)
		}
	}
	if !slices.Equal(BrewLabels, []string{"homebrew.mxcl.llama.cpp"}) {
		t.Fatalf("got %v", BrewLabels)
	}
}

func TestBrewServiceIsAbsentWhenNoLabelIsLoaded(t *testing.T) {
	if anyLoaded(BrewLabels, func(string) bool { return false }) {
		t.Fatal("found a brew service that is not loaded")
	}
}
