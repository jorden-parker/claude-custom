package snapshot

import (
	"fmt"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

type Setting struct {
	Name        string `json:"name"`
	Summary     string `json:"summary"`
	Current     string `json:"current"`
	Set         bool   `json:"set"`
	Recommended string `json:"recommended"`
}

type Snapshot struct {
	Path      string    `json:"path"`
	Exists    bool      `json:"exists"`
	Overrides string    `json:"overrides"`
	Variables []Setting `json:"variables"`
	Conflicts []string  `json:"conflicts"`
}

func Build(plist, overridesPath string, recommended map[string]string, conflicts []string) (Snapshot, error) {
	_, exists, err := launchd.Load(plist)
	if err != nil {
		return Snapshot{}, fmt.Errorf("reading %s: %w", plist, err)
	}
	overrides, err := variables.Load(overridesPath)
	if err != nil {
		return Snapshot{}, fmt.Errorf("reading %s: %w", overridesPath, err)
	}
	return Snapshot{
		Path:      plist,
		Exists:    exists,
		Overrides: overridesPath,
		Variables: settingsFor(recommended, overrides),
		Conflicts: nonNil(conflicts),
	}, nil
}

func settingsFor(recommended, overrides map[string]string) []Setting {
	current := variables.Effective(recommended, overrides)
	names := variables.Names(current)
	found := make([]Setting, 0, len(names))
	for _, name := range names {
		_, set := overrides[name]
		found = append(found, Setting{
			Name:        name,
			Summary:     variables.Summary(name),
			Current:     current[name],
			Set:         set,
			Recommended: recommended[name],
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
