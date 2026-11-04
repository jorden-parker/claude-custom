package profiles

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Profile struct {
	Size  string
	Model string
	Base  string
}

type sizeEntry struct {
	Base string `json:"base"`
}

func Load(dir string) ([]Profile, error) {
	sizes, err := readSizes(filepath.Join(dir, "sizes.json"))
	if err != nil {
		return nil, err
	}
	settingsPaths, err := filepath.Glob(filepath.Join(dir, "settings.*.json"))
	if err != nil {
		return nil, err
	}
	sort.Strings(settingsPaths)
	var found []Profile
	for _, settingsPath := range settingsPaths {
		size := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(settingsPath), "settings."), ".json")
		entry, configured := sizes[size]
		if !configured {
			continue
		}
		model, err := readModel(settingsPath)
		if err != nil {
			return nil, err
		}
		found = append(found, Profile{Size: size, Model: model, Base: entry.Base})
	}
	return found, nil
}

func readSizes(sizesPath string) (map[string]sizeEntry, error) {
	data, err := os.ReadFile(sizesPath)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var sizes map[string]sizeEntry
	if err := json.Unmarshal(data, &sizes); err != nil {
		return nil, fmt.Errorf("%s: %w", sizesPath, err)
	}
	return sizes, nil
}

func readModel(settingsPath string) (string, error) {
	data, err := os.ReadFile(settingsPath)
	if err != nil {
		return "", err
	}
	var settings struct {
		Model string `json:"model"`
	}
	if err := json.Unmarshal(data, &settings); err != nil {
		return "", fmt.Errorf("%s: %w", settingsPath, err)
	}
	if settings.Model == "" {
		return "", fmt.Errorf("%s: no model name", settingsPath)
	}
	return settings.Model, nil
}
