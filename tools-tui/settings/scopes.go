package settings

import (
	"path/filepath"
	"slices"
)

type File struct {
	Label string
	Path  string
}

func Files(home, cwd, custom string) []File {
	scopes := []File{
		{Label: "user", Path: filepath.Join(home, ".claude", "settings.json")},
		{Label: "project", Path: filepath.Join(cwd, ".claude", "settings.json")},
		{Label: "local", Path: filepath.Join(cwd, ".claude", "settings.local.json")},
	}
	var files []File
	for _, scope := range scopes {
		if !containsPath(files, scope.Path) {
			files = append(files, scope)
		}
	}
	customPath := absolute(cwd, custom)
	if containsPath(files, customPath) {
		return files
	}
	return append([]File{{Label: "custom", Path: customPath}}, files...)
}

func absolute(cwd, path string) string {
	if filepath.IsAbs(path) {
		return filepath.Clean(path)
	}
	return filepath.Join(cwd, path)
}

func containsPath(files []File, path string) bool {
	return slices.ContainsFunc(files, func(f File) bool { return f.Path == path })
}

func ResolvePath(home, cwd, arg string) string {
	for _, scope := range Files(home, cwd, arg) {
		if scope.Label == arg {
			return scope.Path
		}
	}
	return arg
}
