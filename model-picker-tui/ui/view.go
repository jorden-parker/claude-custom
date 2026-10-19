package ui

import (
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"

	"github.com/jordenparker/claude-custom/model-picker-tui/profiles"
)

var (
	titleStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	mutedStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	selectedStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	sizeStyle     = lipgloss.NewStyle().Width(6)
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
	return tea.NewView(b.String())
}

func (m Model) row(profile profiles.Profile, selected bool) string {
	details := mutedStyle.Render(profile.Model + "  from " + profile.Base)
	if selected {
		return selectedStyle.Render("> "+sizeStyle.Render(profile.Size)) + details
	}
	return "  " + sizeStyle.Render(profile.Size) + details
}

func (m Model) sideRow() string {
	label := "Set up side model  "
	details := mutedStyle.Render(m.side.Base + " → " + m.side.Name)
	if m.onSideRow() {
		return selectedStyle.Render("> "+label) + details
	}
	return "  " + label + details
}

func (m Model) embeddingRow() string {
	label := "Set up embedding model  "
	details := mutedStyle.Render(m.embedding)
	if m.onEmbeddingRow() {
		return selectedStyle.Render("> "+label) + details
	}
	return "  " + label + details
}
