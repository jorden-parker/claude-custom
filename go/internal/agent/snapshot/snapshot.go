package snapshot

import (
	"fmt"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

type Variable struct {
	Name        string `json:"name"`
	Summary     string `json:"summary"`
	Current     string `json:"current"`
	Set         bool   `json:"set"`
	Recommended string `json:"recommended"`
}

type Snapshot struct {
	Path      string     `json:"path"`
	Exists    bool       `json:"exists"`
	Variables []Variable `json:"variables"`
	Conflicts []string   `json:"conflicts"`
}

func Build(path string, serverEnv map[string]string, conflicts []string) (Snapshot, error) {
	current, exists, err := launchd.Load(path)
	if err != nil {
		return Snapshot{}, fmt.Errorf("reading %s: %w", path, err)
	}
	return Snapshot{
		Path:      path,
		Exists:    exists,
		Variables: variablesFor(current, serverEnv),
		Conflicts: nonNil(conflicts),
	}, nil
}

func variablesFor(current, serverEnv map[string]string) []Variable {
	names := variables.Names(current, serverEnv)
	found := make([]Variable, 0, len(names))
	for _, name := range names {
		value, set := current[name]
		found = append(found, Variable{
			Name:        name,
			Summary:     variables.Summary(name),
			Current:     value,
			Set:         set,
			Recommended: serverEnv[name],
		})
	}
	return found
}

func nonNil(conflicts []string) []string {
	if conflicts == nil {
		return []string{}
	}
	return conflicts
}
