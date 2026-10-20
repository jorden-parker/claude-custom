package ui

import (
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/jordenparker/claude-custom/go/internal/picker/profiles"
)

const (
	sideLabel      = "Set up side model"
	embeddingLabel = "Set up embedding model"
)

var (
	titleStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	mutedStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	selectedStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
)

func (m Model) View() tea.View {
	var b strings.Builder
	b.WriteString(titleStyle.Render("Pick an Ollama model") + "\n\n")
	for i, profile := range m.profiles {
		b.WriteString(m.row(profile, i == m.cursor) + "\n")
	}
	if m.side.Configured() {
		b.WriteString(m.sideRow() + "\n")
	}
	b.WriteString(m.embeddingRow() + "\n")
	if m.status != "" {
		b.WriteString("\n" + mutedStyle.Render(m.status) + "\n")
	}
	b.WriteString("\n" + m.help.View(m.keys) + "\n")
	v := tea.NewView(m.fitToWidth(b.String()))
	v.AltScreen = true
	return v
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

func (m Model) row(profile profiles.Profile, selected bool) string {
	return m.line(profile.Size, profile.Model+"  from "+profile.Base, selected)
}

func (m Model) sideRow() string {
	return m.line(sideLabel, m.side.Base+" → "+m.side.Name, m.onSideRow())
}

func (m Model) embeddingRow() string {
	return m.line(embeddingLabel, m.embedding, m.onEmbeddingRow())
}

func (m Model) line(label, details string, selected bool) string {
	padded := pad(label, m.labelWidth()) + "  "
	if selected {
		return selectedStyle.Render("> "+padded) + mutedStyle.Render(details)
	}
	return "  " + padded + mutedStyle.Render(details)
}

func (m Model) labelWidth() int {
	width := lipgloss.Width(embeddingLabel)
	if m.side.Configured() {
		width = max(width, lipgloss.Width(sideLabel))
	}
	for _, profile := range m.profiles {
		width = max(width, lipgloss.Width(profile.Size))
	}
	return width
}

func pad(text string, width int) string {
	return text + strings.Repeat(" ", max(0, width-lipgloss.Width(text)))
}
