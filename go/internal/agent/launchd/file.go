package launchd

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/jordenparker/claude-custom/go/internal/history"
)

const (
	Label    = "local.ollama"
	fileMode = 0o644
)

func DefaultPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "Library", "LaunchAgents", Label+".plist"), nil
}

func DefaultLogPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "Library", "Logs", "ollama.log"), nil
}

func Load(path string) (map[string]string, bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return map[string]string{}, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	env, err := ReadEnv(data)
	return env, err == nil, err
}

func Save(path string, agent Agent) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data := Render(agent)
	if err := history.RecordWrite("launch-agent", path, data); err != nil {
		return err
	}
	temp, err := os.CreateTemp(filepath.Dir(path), ".agent-*.plist")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	if _, err := temp.Write(data); err != nil {
		temp.Close()
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(temp.Name(), fileMode); err != nil {
		return err
	}
	return os.Rename(temp.Name(), path)
}
