package launchd

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"

	"github.com/jordenparker/claude-custom/go/internal/history"
)

const (
	Label    = "local.llama-server"
	fileMode = 0o644
)

func DefaultPath() (string, error) {
	if path := os.Getenv("LLAMA_SERVER_PLIST"); path != "" {
		return path, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "Library", "LaunchAgents", Label+".plist"), nil
}

func Load(path string) ([]byte, bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	return data, true, nil
}

func ModelsMax(path string) (string, bool, error) {
	data, found, err := Load(path)
	if err != nil || !found {
		return "", false, err
	}
	arguments, err := ReadArguments(data)
	if err != nil {
		return "", false, err
	}
	at := slices.Index(arguments, "--models-max")
	if at < 0 || at+1 >= len(arguments) {
		return "", false, nil
	}
	return arguments[at+1], true, nil
}

func Save(path string, agent Agent) (bool, error) {
	data := Render(agent)
	current, found, err := Load(path)
	if err != nil {
		return false, err
	}
	if found && bytes.Equal(current, data) {
		return false, nil
	}
	return true, write(path, data)
}

func write(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
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
