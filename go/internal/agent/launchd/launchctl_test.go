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
	if got := ServiceTarget(501, BrewLabel); got != "gui/501/homebrew.mxcl.ollama" {
		t.Fatalf("got %q", got)
	}
}
