package catalog

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

type Snapshot struct {
	Source   string    `json:"source"`
	SyncedAt time.Time `json:"syncedAt"`
	Tools    []Tool    `json:"tools"`
}

func DefaultSnapshotPath() (string, error) {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(cacheDir, "claude-tools", "tools.json"), nil
}

func LoadSnapshot(path string) (Snapshot, error) {
	var snapshot Snapshot
	data, err := os.ReadFile(path)
	if err != nil {
		return snapshot, err
	}
	err = json.Unmarshal(data, &snapshot)
	return snapshot, err
}

func SaveSnapshot(path string, snapshot Snapshot) error {
	data, err := json.MarshalIndent(snapshot, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

func Diff(before, after []Tool) (added, dropped []string) {
	return missingFrom(before, after), missingFrom(after, before)
}

func missingFrom(reference, candidates []Tool) []string {
	known := make(map[string]bool, len(reference))
	for _, tool := range reference {
		known[tool.Name] = true
	}
	var missing []string
	for _, tool := range candidates {
		if !known[tool.Name] {
			missing = append(missing, tool.Name)
		}
	}
	return missing
}
