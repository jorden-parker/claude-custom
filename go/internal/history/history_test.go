package history

import (
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

var fixedNow = time.Date(2026, 10, 26, 9, 30, 0, 0, time.UTC)

func enableRecording(t *testing.T) {
	t.Helper()
	t.Setenv("CLAUDE_CUSTOM_HISTORY", "")
	t.Setenv("CLAUDE_CUSTOM_CHANGE_SOURCE", "")
}

func recordFirstSettingsWrite(t *testing.T, dir string) Entry {
	t.Helper()
	entry, recorded, err := Record(dir, Change{Kind: "settings", Path: "/x/settings.json", After: []byte("{}")}, fixedNow)
	if err != nil || !recorded {
		t.Fatalf("Record = %v, %v, want recorded", recorded, err)
	}
	return entry
}

func TestFirstWriteRecordsNilBefore(t *testing.T) {
	enableRecording(t)
	dir := filepath.Join(t.TempDir(), "history")

	entry, recorded, err := Record(dir, Change{Kind: "settings", Path: "/x/settings.json", After: []byte("{}")}, fixedNow)

	if err != nil || !recorded {
		t.Fatalf("Record = %v, %v, want recorded", recorded, err)
	}
	if entry.Before != nil {
		t.Errorf("Before = %v, want nil", *entry.Before)
	}
	if entry.Source != "terminal" || entry.Kind != "settings" || entry.Path != "/x/settings.json" {
		t.Errorf("entry = %+v", entry)
	}
	if !strings.HasPrefix(entry.ID, "20261026-093000-settings-") {
		t.Errorf("ID = %q, want UTC timestamp prefix", entry.ID)
	}
}

func TestSecondWriteRecordsBothFilesWithExactBytes(t *testing.T) {
	enableRecording(t)
	dir := filepath.Join(t.TempDir(), "history")
	first := recordFirstSettingsWrite(t, dir)

	entry, recorded, err := Record(dir, Change{Kind: "settings", Path: "/x/settings.json", Before: []byte("{}"), After: []byte("{\"a\":1}\n"), Existed: true}, fixedNow.Add(time.Minute))

	if err != nil || !recorded {
		t.Fatalf("Record = %v, %v, want recorded", recorded, err)
	}
	if entry.Before == nil || *entry.Before != entry.ID+".before" || entry.After != entry.ID+".after" {
		t.Fatalf("file names = %v, %q", entry.Before, entry.After)
	}
	if got := readFile(t, filepath.Join(dir, *entry.Before)); got != "{}" {
		t.Errorf("before bytes = %q", got)
	}
	if got := readFile(t, filepath.Join(dir, entry.After)); got != "{\"a\":1}\n" {
		t.Errorf("after bytes = %q", got)
	}
	if entry.ID == first.ID {
		t.Errorf("second ID repeats the first: %s", entry.ID)
	}
}

func TestUnchangedBytesRecordNothing(t *testing.T) {
	enableRecording(t)
	dir := filepath.Join(t.TempDir(), "history")

	_, recorded, err := Record(dir, Change{Kind: "settings", Path: "/x", Before: []byte("same"), After: []byte("same"), Existed: true}, fixedNow)

	if err != nil || recorded {
		t.Fatalf("Record = %v, %v, want nothing recorded", recorded, err)
	}
	if _, err := os.Stat(filepath.Join(dir, "index.jsonl")); !os.IsNotExist(err) {
		t.Errorf("index exists after unchanged write: %v", err)
	}
}

func TestOptOutRecordsNothing(t *testing.T) {
	enableRecording(t)
	t.Setenv("CLAUDE_CUSTOM_HISTORY", "off")
	dir := filepath.Join(t.TempDir(), "history")

	_, recorded, err := Record(dir, Change{Kind: "settings", Path: "/x", After: []byte("{}")}, fixedNow)

	if err != nil || recorded {
		t.Fatalf("Record = %v, %v, want nothing recorded", recorded, err)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Errorf("folder exists with recording off: %v", err)
	}
}

func TestOnlyOffDisablesRecording(t *testing.T) {
	enableRecording(t)
	t.Setenv("CLAUDE_CUSTOM_HISTORY", "no")

	if !Enabled() {
		t.Error("Enabled() = false for CLAUDE_CUSTOM_HISTORY=no, want true")
	}
}

func TestSourceComesFromEnvironment(t *testing.T) {
	enableRecording(t)
	t.Setenv("CLAUDE_CUSTOM_CHANGE_SOURCE", "console")
	dir := filepath.Join(t.TempDir(), "history")

	entry := recordFirstSettingsWrite(t, dir)

	if entry.Source != "console" {
		t.Errorf("Source = %q, want console", entry.Source)
	}
}

func TestModesAreOwnerOnly(t *testing.T) {
	enableRecording(t)
	dir := filepath.Join(t.TempDir(), "history")
	entry := recordFirstSettingsWrite(t, dir)

	assertMode(t, dir, 0o700)
	assertMode(t, filepath.Join(dir, "index.jsonl"), 0o600)
	assertMode(t, filepath.Join(dir, entry.After), 0o600)
}

func TestSymlinkedIndexIsRefused(t *testing.T) {
	enableRecording(t)
	dir := filepath.Join(t.TempDir(), "history")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(t.TempDir(), "elsewhere.jsonl")
	if err := os.WriteFile(outside, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(dir, "index.jsonl")); err != nil {
		t.Fatal(err)
	}

	_, recorded, err := Record(dir, Change{Kind: "settings", Path: "/x", After: []byte("{}")}, fixedNow)

	if err == nil || recorded {
		t.Fatalf("Record = %v, %v, want refusal", recorded, err)
	}
	if got := readFile(t, outside); got != "" {
		t.Errorf("symlink target was written: %q", got)
	}
}

func TestSymlinkedFolderIsRefused(t *testing.T) {
	enableRecording(t)
	real := t.TempDir()
	link := filepath.Join(t.TempDir(), "history")
	if err := os.Symlink(real, link); err != nil {
		t.Fatal(err)
	}

	_, recorded, err := Record(link, Change{Kind: "settings", Path: "/x", After: []byte("{}")}, fixedNow)

	if err == nil || recorded {
		t.Fatalf("Record = %v, %v, want refusal", recorded, err)
	}
}

func TestListIsNewestFirst(t *testing.T) {
	enableRecording(t)
	dir := filepath.Join(t.TempDir(), "history")
	for i, after := range []string{"one", "two", "three"} {
		if _, _, err := Record(dir, Change{Kind: "settings", Path: "/x", After: []byte(after)}, fixedNow.Add(time.Duration(i)*time.Minute)); err != nil {
			t.Fatal(err)
		}
	}

	entries, err := List(dir)

	if err != nil {
		t.Fatal(err)
	}
	var afters []string
	for _, entry := range entries {
		afters = append(afters, readFile(t, filepath.Join(dir, entry.After)))
	}
	if want := []string{"three", "two", "one"}; !reflect.DeepEqual(afters, want) {
		t.Errorf("order = %v, want %v", afters, want)
	}
}

func TestListSkipsBadLinesAndMissingFolderIsEmpty(t *testing.T) {
	enableRecording(t)
	dir := filepath.Join(t.TempDir(), "history")
	if entries, err := List(dir); err != nil || len(entries) != 0 {
		t.Fatalf("List(missing) = %v, %v, want empty", entries, err)
	}
	recordFirstSettingsWrite(t, dir)
	appendToIndex(t, dir, "not json\n")

	entries, err := List(dir)

	if err != nil || len(entries) != 1 {
		t.Fatalf("List = %v, %v, want one entry", entries, err)
	}
}

func TestEntryRoundTripsThroughJSON(t *testing.T) {
	enableRecording(t)
	dir := filepath.Join(t.TempDir(), "history")
	recordFirstSettingsWrite(t, dir)

	line := strings.TrimSpace(readFile(t, filepath.Join(dir, "index.jsonl")))
	var fields map[string]any
	if err := json.Unmarshal([]byte(line), &fields); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"id", "at", "kind", "path", "source", "before", "after"} {
		if _, ok := fields[key]; !ok {
			t.Errorf("index line lacks %q: %s", key, line)
		}
	}
}

func appendToIndex(t *testing.T, dir, text string) {
	t.Helper()
	file, err := os.OpenFile(filepath.Join(dir, "index.jsonl"), os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	if _, err := file.WriteString(text); err != nil {
		t.Fatal(err)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func assertMode(t *testing.T, path string, want fs.FileMode) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != want {
		t.Errorf("%s mode = %o, want %o", path, got, want)
	}
}
