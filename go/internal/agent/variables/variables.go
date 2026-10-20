package variables

import (
	"errors"
	"fmt"
	"io/fs"
	"maps"
	"os"
	"slices"
	"strings"
)

type Variable struct {
	Name    string
	Summary string
}

var Known = []Variable{
	{"OLLAMA_KEEP_ALIVE", "how long an idle model stays loaded (-1 = forever)"},
	{"OLLAMA_MAX_LOADED_MODELS", "models kept in memory at once"},
	{"OLLAMA_NUM_PARALLEL", "requests served at once per model (each needs its own KV cache)"},
	{"OLLAMA_MAX_QUEUE", "requests queued before new ones are rejected"},
	{"OLLAMA_CONTEXT_LENGTH", "default context window when a model sets none"},
	{"OLLAMA_FLASH_ATTENTION", "1 enables flash attention"},
	{"OLLAMA_KV_CACHE_TYPE", "KV cache precision: f16, q8_0, q4_0"},
	{"OLLAMA_HOST", "address the server listens on"},
	{"OLLAMA_ORIGINS", "extra allowed CORS origins"},
	{"OLLAMA_MODELS", "directory that holds the models"},
	{"OLLAMA_DEBUG", "1 logs debug output"},
}

func Summary(name string) string {
	for _, variable := range Known {
		if variable.Name == name {
			return variable.Summary
		}
	}
	return ""
}

func Names(envs ...map[string]string) []string {
	names := make([]string, 0, len(Known))
	extras := map[string]bool{}
	for _, variable := range Known {
		names = append(names, variable.Name)
	}
	for _, env := range envs {
		for name := range env {
			if !slices.Contains(names, name) {
				extras[name] = true
			}
		}
	}
	return append(names, slices.Sorted(maps.Keys(extras))...)
}

func LoadServerEnv(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return map[string]string{}, nil
	}
	if err != nil {
		return nil, err
	}
	return ParseServerEnv(data)
}

func ParseServerEnv(data []byte) (map[string]string, error) {
	env := map[string]string{}
	for number, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		name, value, ok := strings.Cut(line, "=")
		if !ok {
			return nil, fmt.Errorf("line %d: expected NAME=value, got %q", number+1, line)
		}
		env[name] = value
	}
	return env, nil
}

func WithServerEnv(current, serverEnv map[string]string) (map[string]string, []string) {
	env := map[string]string{}
	maps.Copy(env, current)
	var changed []string
	for _, name := range slices.Sorted(maps.Keys(serverEnv)) {
		if env[name] != serverEnv[name] {
			env[name] = serverEnv[name]
			changed = append(changed, name)
		}
	}
	return env, changed
}
