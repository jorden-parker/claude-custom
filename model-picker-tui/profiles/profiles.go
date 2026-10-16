package profiles

import (
	"bufio"
	"encoding/json"
	"fmt"
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

func Load(dir string) ([]Profile, error) {
	settingsPaths, err := filepath.Glob(filepath.Join(dir, "settings.*.json"))
	if err != nil {
		return nil, err
	}
	sort.Strings(settingsPaths)
	var found []Profile
	for _, settingsPath := range settingsPaths {
		size := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(settingsPath), "settings."), ".json")
		modelfilePath := filepath.Join(dir, "Modelfile."+size)
		if _, err := os.Stat(modelfilePath); err != nil {
			continue
		}
		profile, err := loadProfile(size, settingsPath, modelfilePath)
		if err != nil {
			return nil, err
		}
		found = append(found, profile)
	}
	return found, nil
}

func loadProfile(size, settingsPath, modelfilePath string) (Profile, error) {
	model, err := readModel(settingsPath)
	if err != nil {
		return Profile{}, err
	}
	base, err := readBase(modelfilePath)
	if err != nil {
		return Profile{}, err
	}
	return Profile{Size: size, Model: model, Base: base}, nil
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

func readBase(modelfilePath string) (string, error) {
	file, err := os.Open(modelfilePath)
	if err != nil {
		return "", err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		if base, ok := strings.CutPrefix(scanner.Text(), "FROM "); ok {
			return strings.TrimSpace(base), nil
		}
	}
	return "", fmt.Errorf("%s: no FROM line", modelfilePath)
}
