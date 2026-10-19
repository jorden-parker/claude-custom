package settings

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

var managed = []string{"Bash", "Read", "WebFetch", "WebSearch"}

func permissionsOf(t *testing.T, data []byte) map[string][]string {
	t.Helper()
	var document struct {
		Permissions map[string]json.RawMessage `json:"permissions"`
	}
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatalf("invalid JSON %s: %v", data, err)
	}
	lists := map[string][]string{}
	for _, key := range []string{"allow", "ask", "deny"} {
		var entries []string
		json.Unmarshal(document.Permissions[key], &entries)
		lists[key] = entries
	}
	return lists
}

func TestReadMapsBareRulesToStates(t *testing.T) {
	data := []byte(`{"permissions":{
		"allow":["Read","WebFetch","Bash(git log *)"],
		"ask":["WebSearch"],
		"deny":["WebFetch","Bash"]}}`)

	states, err := Read(data, managed)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]ToolState{
		"Bash":      {Permission: Deny},
		"Read":      {Permission: Allow},
		"WebFetch":  {Permission: Allow, Disabled: true},
		"WebSearch": {Permission: Ask},
	}
	if !reflect.DeepEqual(states, want) {
		t.Fatalf("got %+v", states)
	}
}

func TestReadTreatsMissingPermissionsAsDefault(t *testing.T) {
	states, err := Read([]byte(`{}`), managed)
	if err != nil {
		t.Fatal(err)
	}
	if states["Bash"] != (ToolState{}) {
		t.Fatalf("got %+v", states["Bash"])
	}
}

func TestReadRejectsInvalidJSON(t *testing.T) {
	if _, err := Read([]byte(`{"permissions":`), managed); err == nil {
		t.Fatal("expected an error")
	}
}

func TestWritePreservesUnmanagedSettingsAndRules(t *testing.T) {
	data := []byte(`{
  "model": "opus",
  "permissions": {
    "allow": ["Bash(git log *)", "Read"],
    "deny": ["Read(./.env)", "mcp__github"],
    "defaultMode": "plan"
  },
  "hooks": {"PreToolUse": []}
}`)

	written, err := Write(data, map[string]ToolState{"Read": {}, "Bash": {Permission: Ask}})
	if err != nil {
		t.Fatal(err)
	}
	lists := permissionsOf(t, written)
	if !reflect.DeepEqual(lists["allow"], []string{"Bash(git log *)"}) {
		t.Fatalf("allow %v", lists["allow"])
	}
	if !reflect.DeepEqual(lists["ask"], []string{"Bash"}) {
		t.Fatalf("ask %v", lists["ask"])
	}
	if !reflect.DeepEqual(lists["deny"], []string{"Read(./.env)", "mcp__github"}) {
		t.Fatalf("deny %v", lists["deny"])
	}
	for _, kept := range []string{`"model": "opus"`, `"defaultMode": "plan"`, `"PreToolUse": []`} {
		if !strings.Contains(string(written), kept) {
			t.Fatalf("lost %s in %s", kept, written)
		}
	}
}

func TestWriteKeepsKeyOrder(t *testing.T) {
	data := []byte(`{"zeta":1,"permissions":{"allow":[]},"alpha":2}`)

	written, _ := Write(data, map[string]ToolState{"Bash": {Permission: Allow}})
	text := string(written)
	if !(strings.Index(text, "zeta") < strings.Index(text, "permissions") && strings.Index(text, "permissions") < strings.Index(text, "alpha")) {
		t.Fatalf("key order changed: %s", text)
	}
}

func TestWriteDisabledKeepsPermissionAlongsideDeny(t *testing.T) {
	written, _ := Write([]byte(`{}`), map[string]ToolState{"WebFetch": {Permission: Allow, Disabled: true}})

	lists := permissionsOf(t, written)
	if !reflect.DeepEqual(lists["deny"], []string{"WebFetch"}) || !reflect.DeepEqual(lists["allow"], []string{"WebFetch"}) {
		t.Fatalf("got %v", lists)
	}
}

func TestWriteThenReadRoundTrips(t *testing.T) {
	want := map[string]ToolState{
		"Bash":      {Permission: Ask, Disabled: true},
		"Read":      {Permission: Allow},
		"WebFetch":  {Permission: Deny},
		"WebSearch": {},
	}
	written, err := Write([]byte(`{}`), want)
	if err != nil {
		t.Fatal(err)
	}
	got, _ := Read(written, managed)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v", got)
	}
}

func TestWriteOmitsEmptyListsThatDidNotExist(t *testing.T) {
	written, _ := Write([]byte(`{"model":"opus"}`), map[string]ToolState{"Bash": {}})
	if strings.Contains(string(written), "permissions") {
		t.Fatalf("created empty permissions: %s", written)
	}
}

func TestWriteDoesNotDuplicateExistingRules(t *testing.T) {
	data := []byte(`{"permissions":{"allow":["Read","Read"]}}`)

	written, _ := Write(data, map[string]ToolState{"Read": {Permission: Allow}})
	if lists := permissionsOf(t, written); !reflect.DeepEqual(lists["allow"], []string{"Read"}) {
		t.Fatalf("allow %v", lists["allow"])
	}
}

func TestSaveWritesThroughSymlinkAndKeepsBackup(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "real.json")
	link := filepath.Join(dir, "settings.json")
	os.WriteFile(target, []byte(`{"old":true}`), 0o600)
	os.Symlink(target, link)

	if err := Save(link, []byte(`{"new":true}`)); err != nil {
		t.Fatal(err)
	}
	if info, _ := os.Lstat(link); info.Mode()&os.ModeSymlink == 0 {
		t.Fatal("symlink was replaced by a regular file")
	}
	if data, _ := os.ReadFile(target); string(data) != `{"new":true}` {
		t.Fatalf("target holds %s", data)
	}
	if info, _ := os.Stat(target); info.Mode().Perm() != 0o600 {
		t.Fatalf("mode changed to %v", info.Mode().Perm())
	}
	if backup, _ := os.ReadFile(target + ".bak"); string(backup) != `{"old":true}` {
		t.Fatalf("backup holds %s", backup)
	}
}

func TestLoadReturnsEmptyObjectForMissingFile(t *testing.T) {
	data, err := Load(filepath.Join(t.TempDir(), "absent.json"))
	if err != nil || string(data) != "{}" {
		t.Fatalf("got %q, %v", data, err)
	}
}

func TestSaveCreatesMissingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".claude", "settings.json")
	if err := Save(path, []byte(`{}`)); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(path); string(data) != "{}" {
		t.Fatalf("got %s", data)
	}
}
