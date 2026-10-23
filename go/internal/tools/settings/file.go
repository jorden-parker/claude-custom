package settings

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

const newFileMode fs.FileMode = 0o644

func DefaultPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".claude", "settings.json"), nil
}

func Load(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return []byte("{}"), nil
	}
	return data, err
}

func Save(path string, data []byte) error {
	target, err := resolveTarget(path)
	if err != nil {
		return err
	}
	mode, err := backUp(target)
	if err != nil {
		return err
	}
	return replaceAtomically(target, data, mode)
}

func resolveTarget(path string) (string, error) {
	target, err := filepath.EvalSymlinks(path)
	if errors.Is(err, fs.ErrNotExist) {
		return path, os.MkdirAll(filepath.Dir(path), 0o755)
	}
	return target, err
}

func backUp(target string) (fs.FileMode, error) {
	original, err := os.ReadFile(target)
	if errors.Is(err, fs.ErrNotExist) {
		return newFileMode, nil
	}
	if err != nil {
		return 0, err
	}
	info, err := os.Stat(target)
	if err != nil {
		return 0, err
	}
	backupPath := target + ".bak"
	if isSymlink(backupPath) {
		return 0, fmt.Errorf("refusing to write backup through symlink %s", backupPath)
	}
	return info.Mode().Perm(), os.WriteFile(backupPath, original, info.Mode().Perm())
}

func isSymlink(path string) bool {
	info, err := os.Lstat(path)
	return err == nil && info.Mode()&fs.ModeSymlink != 0
}

func replaceAtomically(target string, data []byte, mode fs.FileMode) error {
	temp, err := os.CreateTemp(filepath.Dir(target), ".settings-*.json")
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
	if err := os.Chmod(temp.Name(), mode); err != nil {
		return err
	}
	return os.Rename(temp.Name(), target)
}
