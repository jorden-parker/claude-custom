package report

import (
	"github.com/jordenparker/claude-custom/go/internal/tools/catalog"
	"github.com/jordenparker/claude-custom/go/internal/tools/settings"
)

type Report struct {
	Path  string `json:"path"`
	Tools []Row  `json:"tools"`
}

type Row struct {
	Name             string `json:"name"`
	Description      string `json:"description"`
	PromptsByDefault bool   `json:"promptsByDefault"`
	Permission       string `json:"permission"`
	Disabled         bool   `json:"disabled"`
}

func Build(settingsPath string, tools []catalog.Tool) (Report, error) {
	data, err := settings.Load(settingsPath)
	if err != nil {
		return Report{}, err
	}
	names := make([]string, 0, len(tools))
	for _, tool := range tools {
		names = append(names, tool.Name)
	}
	states, err := settings.Read(data, names)
	if err != nil {
		return Report{}, err
	}
	rows := make([]Row, 0, len(tools))
	for _, tool := range tools {
		state := states[tool.Name]
		rows = append(rows, Row{
			Name:             tool.Name,
			Description:      tool.Description,
			PromptsByDefault: tool.PromptsByDefault,
			Permission:       state.Permission.String(),
			Disabled:         state.Disabled,
		})
	}
	return Report{Path: settingsPath, Tools: rows}, nil
}
