package history

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"time"
)

const (
	folderMode    fs.FileMode = 0o700
	fileMode      fs.FileMode = 0o600
	indexName                 = "index.jsonl"
	idTimeLayout              = "20060102-150405"
	defaultSource             = "terminal"
)

var kindPattern = regexp.MustCompile(`^[a-z][a-z-]*$`)

type Change struct {
	Kind    string
	Path    string
	Before  []byte
	After   []byte
	Existed bool
}

type Entry struct {
	ID     string  `json:"id"`
	At     string  `json:"at"`
	Kind   string  `json:"kind"`
	Path   string  `json:"path"`
	Source string  `json:"source"`
	Before *string `json:"before"`
	After  string  `json:"after"`
}

func Dir() string {
	if state := os.Getenv("CLAUDE_CONSOLE_STATE_DIR"); state != "" {
		return filepath.Join(state, "history")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".local", "share", "claude-custom", "console", "history")
}

func Enabled() bool {
	return os.Getenv("CLAUDE_CUSTOM_HISTORY") != "off"
}

func Record(dir string, change Change, now time.Time) (Entry, bool, error) {
	if !Enabled() || (change.Existed && bytes.Equal(change.Before, change.After)) {
		return Entry{}, false, nil
	}
	if dir == "" {
		return Entry{}, false, errors.New("history folder is unknown: no home directory")
	}
	if !kindPattern.MatchString(change.Kind) {
		return Entry{}, false, fmt.Errorf("invalid history kind %q", change.Kind)
	}
	entry, err := newEntry(change, now)
	if err != nil {
		return Entry{}, false, err
	}
	if err := ensureFolder(dir); err != nil {
		return Entry{}, false, err
	}
	if err := writeData(dir, entry, change); err != nil {
		return Entry{}, false, err
	}
	if err := appendIndex(dir, entry); err != nil {
		return Entry{}, false, err
	}
	return entry, true, nil
}

func RecordWrite(kind, path string, after []byte) error {
	before, existed, err := readCurrent(path)
	if err != nil {
		return err
	}
	_, _, err = Record(Dir(), Change{Kind: kind, Path: path, Before: before, After: after, Existed: existed}, time.Now())
	return err
}

func List(dir string) ([]Entry, error) {
	file, err := os.Open(filepath.Join(dir, indexName))
	if errors.Is(err, fs.ErrNotExist) {
		return []Entry{}, nil
	}
	if err != nil {
		return nil, err
	}
	defer file.Close()
	entries := []Entry{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		var entry Entry
		if json.Unmarshal(scanner.Bytes(), &entry) == nil && entry.ID != "" {
			entries = append(entries, entry)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	slices.Reverse(entries)
	return entries, nil
}

func readCurrent(path string) ([]byte, bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, false, nil
	}
	return data, err == nil, err
}

func newEntry(change Change, now time.Time) (Entry, error) {
	suffix, err := randomSuffix()
	if err != nil {
		return Entry{}, err
	}
	utc := now.UTC()
	id := utc.Format(idTimeLayout) + "-" + change.Kind + "-" + suffix
	entry := Entry{
		ID:     id,
		At:     utc.Format(time.RFC3339),
		Kind:   change.Kind,
		Path:   change.Path,
		Source: changeSource(),
		After:  id + ".after",
	}
	if change.Existed {
		before := id + ".before"
		entry.Before = &before
	}
	return entry, nil
}

func randomSuffix() (string, error) {
	raw := make([]byte, 2)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return hex.EncodeToString(raw), nil
}

func changeSource() string {
	if source := os.Getenv("CLAUDE_CUSTOM_CHANGE_SOURCE"); source != "" {
		return source
	}
	return defaultSource
}

func ensureFolder(dir string) error {
	if isSymlink(dir) {
		return fmt.Errorf("refusing history folder that is a symlink: %s", dir)
	}
	return os.MkdirAll(dir, folderMode)
}

func writeData(dir string, entry Entry, change Change) error {
	if change.Existed {
		if err := writeNewFile(filepath.Join(dir, *entry.Before), change.Before); err != nil {
			return err
		}
	}
	return writeNewFile(filepath.Join(dir, entry.After), change.After)
}

func writeNewFile(path string, data []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, fileMode)
	if err != nil {
		return err
	}
	if _, err := file.Write(data); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}

func appendIndex(dir string, entry Entry) error {
	path := filepath.Join(dir, indexName)
	if isSymlink(path) {
		return fmt.Errorf("refusing history index that is a symlink: %s", path)
	}
	line, err := json.Marshal(entry)
	if err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, fileMode)
	if err != nil {
		return err
	}
	if _, err := file.Write(append(line, '\n')); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}

func isSymlink(path string) bool {
	info, err := os.Lstat(path)
	return err == nil && info.Mode()&fs.ModeSymlink != 0
}
