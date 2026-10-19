package catalog

import (
	"errors"
	"regexp"
	"strings"
)

type Tool struct {
	Name             string `json:"name"`
	Description      string `json:"description"`
	PromptsByDefault bool   `json:"promptsByDefault"`
}

const toolsTableHeaderPrefix = "| Tool | Description |"
const escapedPipePlaceholder = "\x00"

var (
	markdownLink       = regexp.MustCompile(`\[([^\]]+)\]\([^)]*\)`)
	retiredDescription = regexp.MustCompile(`(?i)^removed\b|\bdeprecated\b`)
)

func Parse(markdown []byte) ([]Tool, error) {
	rows := toolsTableRows(strings.Split(string(markdown), "\n"))
	if len(rows) == 0 {
		return nil, errors.New("tools table not found in the docs page")
	}
	var tools []Tool
	for _, row := range rows {
		tool, ok := parseRow(row)
		if ok && !retiredDescription.MatchString(tool.Description) {
			tools = append(tools, tool)
		}
	}
	return tools, nil
}

func toolsTableRows(lines []string) []string {
	for i, line := range lines {
		if strings.HasPrefix(line, toolsTableHeaderPrefix) {
			return rowsAfterSeparator(lines[i+2:])
		}
	}
	return nil
}

func rowsAfterSeparator(lines []string) []string {
	var rows []string
	for _, line := range lines {
		if !strings.HasPrefix(line, "|") {
			break
		}
		rows = append(rows, line)
	}
	return rows
}

func parseRow(row string) (Tool, bool) {
	cells := splitCells(row)
	if len(cells) != 3 {
		return Tool{}, false
	}
	name := strings.Trim(cells[0], "`")
	if name == "" {
		return Tool{}, false
	}
	return Tool{
		Name:             name,
		Description:      plainText(cells[1]),
		PromptsByDefault: strings.EqualFold(cells[2], "yes"),
	}, true
}

func splitCells(row string) []string {
	protected := strings.ReplaceAll(row, `\|`, escapedPipePlaceholder)
	parts := strings.Split(strings.Trim(protected, "| "), "|")
	cells := make([]string, len(parts))
	for i, part := range parts {
		cells[i] = strings.TrimSpace(strings.ReplaceAll(part, escapedPipePlaceholder, "|"))
	}
	return cells
}

func plainText(markdown string) string {
	withoutLinks := markdownLink.ReplaceAllString(markdown, "$1")
	return strings.ReplaceAll(withoutLinks, "`", "")
}
