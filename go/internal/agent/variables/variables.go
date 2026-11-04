package variables

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/jordenparker/claude-custom/go/internal/history"
)

type Setting struct {
	Name    string
	Summary string
}

const (
	ModelsMax     = "models-max"
	sharedSection = "*"
	routerSection = "router"
	maxValueBytes = 256
	fileMode      = 0o600
)

var Known = []Setting{
	{ModelsMax, "models the router keeps loaded at once (chat plus embedding needs 2)"},
	{"n-gpu-layers", "layers offloaded to the GPU (99 = all)"},
	{"flash-attn", "flash attention: on, off or auto"},
	{"batch-size", "logical batch size for prompt processing"},
	{"ubatch-size", "physical batch size for prompt processing"},
	{"cache-type-k", "KV cache precision for keys: f16, q8_0, q4_0"},
	{"cache-type-v", "KV cache precision for values: f16, q8_0, q4_0"},
	{"parallel", "requests served at once per model (each needs its own KV cache)"},
	{"cache-ram", "MiB of host memory for the prompt cache"},
	{"ctx-checkpoints", "context checkpoints kept per slot"},
	{"checkpoint-min-step", "tokens between context checkpoints"},
	{"cache-reuse", "minimum chunk reused from the cache by shifting"},
	{"prio", "process priority: 0 normal to 3 realtime"},
	{"sleep-idle-seconds", "idle seconds before a model sleeps (-1 = never)"},
	{"jinja", "use the model's Jinja chat template"},
}

func Summary(name string) string {
	for _, setting := range Known {
		if setting.Name == name {
			return setting.Summary
		}
	}
	return ""
}

func ParseAssignment(text string) (string, string, error) {
	name, value, ok := strings.Cut(text, "=")
	if !ok {
		return "", "", fmt.Errorf("expected KEY=value, got %q", text)
	}
	if !isKnown(name) {
		return "", "", fmt.Errorf("unknown setting %q", name)
	}
	if value == "" {
		return "", "", fmt.Errorf("%s: value is empty", name)
	}
	if strings.ContainsAny(value, "\n\r\x00[]") {
		return "", "", fmt.Errorf("%s: value has a newline, NUL or bracket", name)
	}
	if len(value) > maxValueBytes {
		return "", "", fmt.Errorf("%s: value is longer than %d bytes", name, maxValueBytes)
	}
	return name, value, nil
}

func isKnown(name string) bool {
	return slices.ContainsFunc(Known, func(setting Setting) bool {
		return setting.Name == name
	})
}

func Names(values ...map[string]string) []string {
	names := make([]string, 0, len(Known))
	extras := map[string]bool{}
	for _, setting := range Known {
		names = append(names, setting.Name)
	}
	for _, found := range values {
		for name := range found {
			if !slices.Contains(names, name) {
				extras[name] = true
			}
		}
	}
	return append(names, slices.Sorted(maps.Keys(extras))...)
}

func Load(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return map[string]string{}, nil
	}
	if err != nil {
		return nil, err
	}
	return Parse(data)
}

func Parse(data []byte) (map[string]string, error) {
	values := map[string]string{}
	section := ""
	for number, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, ";") || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = line[1 : len(line)-1]
			continue
		}
		name, value, ok := strings.Cut(line, "=")
		if !ok {
			return nil, fmt.Errorf("line %d: expected key = value, got %q", number+1, line)
		}
		name, value = strings.TrimSpace(name), strings.TrimSpace(value)
		if section == sharedSection || (section == routerSection && name == ModelsMax) {
			values[name] = value
		}
	}
	return values, nil
}

func Effective(recommended, overrides map[string]string) map[string]string {
	values := maps.Clone(recommended)
	if values == nil {
		values = map[string]string{}
	}
	maps.Copy(values, overrides)
	return values
}

func Overrides(recommended, values map[string]string) map[string]string {
	overrides := map[string]string{}
	for name, value := range values {
		if recommended[name] != value {
			overrides[name] = value
		}
	}
	return overrides
}

func Render(overrides map[string]string) []byte {
	var b strings.Builder
	shared := slices.Sorted(maps.Keys(overrides))
	shared = slices.DeleteFunc(shared, func(name string) bool { return name == ModelsMax })
	if len(shared) > 0 {
		b.WriteString("[" + sharedSection + "]\n")
		for _, name := range shared {
			b.WriteString(name + " = " + overrides[name] + "\n")
		}
	}
	if value, set := overrides[ModelsMax]; set {
		if b.Len() > 0 {
			b.WriteString("\n")
		}
		b.WriteString("[" + routerSection + "]\n" + ModelsMax + " = " + value + "\n")
	}
	return []byte(b.String())
}

func Save(path string, overrides map[string]string) error {
	data := Render(overrides)
	current, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		if len(data) == 0 {
			return nil
		}
	} else if err != nil {
		return err
	} else if bytes.Equal(current, data) {
		return nil
	}
	return write(path, data)
}

func write(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	if err := history.RecordWrite("server-settings", path, data); err != nil {
		return err
	}
	temp, err := os.CreateTemp(filepath.Dir(path), ".server-*.ini")
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
