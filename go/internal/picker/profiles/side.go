package profiles

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

const sideModelfileName = "side.Modelfile"

type SideModel struct {
	Name      string
	Base      string
	Modelfile string
}

func (s SideModel) Configured() bool {
	return s.Name != ""
}

func LoadSide(dir string) (SideModel, error) {
	modelfilePath := filepath.Join(dir, sideModelfileName)
	if _, err := os.Stat(modelfilePath); errors.Is(err, os.ErrNotExist) {
		return SideModel{}, nil
	}
	base, err := readBase(modelfilePath)
	if err != nil {
		return SideModel{}, err
	}
	name, err := readHaikuModel(dir)
	if err != nil {
		return SideModel{}, err
	}
	return SideModel{Name: name, Base: base, Modelfile: modelfilePath}, nil
}

func readHaikuModel(dir string) (string, error) {
	settingsPaths, err := filepath.Glob(filepath.Join(dir, "settings.*.json"))
	if err != nil {
		return "", err
	}
	sort.Strings(settingsPaths)
	names := map[string]bool{}
	for _, settingsPath := range settingsPaths {
		name, err := readHaikuSetting(settingsPath)
		if err != nil {
			return "", err
		}
		if name != "" {
			names[name] = true
		}
	}
	return singleName(names, dir)
}

func readHaikuSetting(settingsPath string) (string, error) {
	data, err := os.ReadFile(settingsPath)
	if err != nil {
		return "", err
	}
	var settings struct {
		Env struct {
			HaikuModel string `json:"ANTHROPIC_DEFAULT_HAIKU_MODEL"`
		} `json:"env"`
	}
	if err := json.Unmarshal(data, &settings); err != nil {
		return "", fmt.Errorf("%s: %w", settingsPath, err)
	}
	return settings.Env.HaikuModel, nil
}

func singleName(names map[string]bool, dir string) (string, error) {
	if len(names) != 1 {
		return "", fmt.Errorf("%s: settings must name exactly one ANTHROPIC_DEFAULT_HAIKU_MODEL for %s, found %d", dir, sideModelfileName, len(names))
	}
	for name := range names {
		return name, nil
	}
	return "", nil
}
