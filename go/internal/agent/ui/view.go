package ui

import (
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

const (
	valueWidth = 12
	unsetLabel = "unset"
)

var (
	titleStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	mutedStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	selectedStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	warningStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
)

func (m Model) View() tea.View {
	var b strings.Builder
	b.WriteString(titleStyle.Render("Ollama LaunchAgent") + "\n")
	b.WriteString(mutedStyle.Render(m.config.Path) + "\n")
	for _, conflict := range m.config.Conflicts {
		b.WriteString(warningStyle.Render("! "+conflict) + "\n")
	}
	b.WriteString("\n")
	for i, name := range m.names {
		b.WriteString(m.row(name, i == m.cursor) + "\n")
	}
	if m.status != "" {
		b.WriteString("\n" + mutedStyle.Render(m.status) + "\n")
	}
	b.WriteString("\n" + m.helpView() + "\n")
	v := tea.NewView(m.fitToWidth(b.String()))
	v.AltScreen = true
	return v
}

func (m Model) helpView() string {
	if m.editing {
		return m.help.View(editKeyMap{keys: m.keys})
	}
	return m.help.View(m.keys)
}

func (m Model) row(name string, selected bool) string {
	label := pad(m.unsavedMarker(name)+name, m.nameWidth()+1) + "  "
	value := pad(m.valueView(name, selected), valueWidth) + "  "
	details := mutedStyle.Render(m.details(name))
	if selected {
		return selectedStyle.Render("> "+label) + value + details
	}
	return "  " + label + value + details
}

func (m Model) valueView(name string, selected bool) string {
	if selected && m.editing {
		return m.input.View()
	}
	if value, set := m.values[name]; set {
		return value
	}
	return mutedStyle.Render(unsetLabel)
}

func (m Model) unsavedMarker(name string) string {
	if m.values[name] != m.saved[name] {
		return "*"
	}
	return " "
}

func (m Model) details(name string) string {
	summary := variables.Summary(name)
	recommended, listed := m.config.ServerEnv[name]
	if !listed || m.values[name] == recommended {
		return summary
	}
	hint := "server.env: " + recommended
	if summary == "" {
		return hint
	}
	return hint + " · " + summary
}

func (m Model) nameWidth() int {
	width := 0
	for _, name := range m.names {
		width = max(width, lipgloss.Width(name))
	}
	return width
}

func (m Model) fitToWidth(content string) string {
	if m.width == 0 {
		return content
	}
	lines := strings.Split(content, "\n")
	for i, line := range lines {
		lines[i] = ansi.Truncate(line, m.width, "…")
	}
	return strings.Join(lines, "\n")
}

func pad(text string, width int) string {
	return text + strings.Repeat(" ", max(0, width-lipgloss.Width(text)))
}
