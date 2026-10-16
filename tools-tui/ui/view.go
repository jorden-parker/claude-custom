package ui

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/ansi"

	"github.com/jordenparker/claude-custom/tools-tui/catalog"
	"github.com/jordenparker/claude-custom/tools-tui/settings"
)

const (
	nameWidth       = 22
	permissionWidth = 16
	contextWidth    = 9
	labelWidth      = 8
	markerWidth     = 8
	chromeLines     = 6
)

var (
	titleStyle     = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	mutedStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	headerStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("250"))
	selectedStyle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	dirtyStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
	statusStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("39"))
	offStyle       = lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Faint(true)
	onStyle        = lipgloss.NewStyle().Foreground(lipgloss.Color("42"))
	permissionLook = map[settings.Permission]lipgloss.Style{
		settings.Default: lipgloss.NewStyle().Foreground(lipgloss.Color("245")),
		settings.Allow:   lipgloss.NewStyle().Foreground(lipgloss.Color("42")).Bold(true),
		settings.Ask:     lipgloss.NewStyle().Foreground(lipgloss.Color("220")).Bold(true),
		settings.Deny:    lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Bold(true),
	}
)

func (m Model) View() tea.View {
	helpView := m.help.View(m.keys)
	header, body := m.headerLine(), m.toolRows(m.visibleRowCount(helpView))
	if m.picking {
		helpView = m.help.View(pickerKeyMap{m.keys})
		header, body = headerStyle.Render("  SETTINGS FILE"), m.fileRows()
	}
	sections := []string{
		m.titleLine(),
		mutedStyle.Render(m.sourceLine()),
		"",
		header,
		body,
		"",
		statusStyle.Render(m.status),
		helpView,
	}
	view := tea.NewView(m.fitToWidth(strings.Join(sections, "\n")))
	view.AltScreen = true
	return view
}

func (m Model) titleLine() string {
	title := titleStyle.Render("Claude Code tools")
	if m.dirty() {
		title += "  " + dirtyStyle.Render("● unsaved")
	}
	return title + "  " + mutedStyle.Render(m.activeFileName())
}

func (m Model) activeFileName() string {
	if index := m.activeFileIndex(); index >= 0 {
		return m.config.SettingsFiles[index].Label + " · " + m.config.SettingsPath
	}
	return m.config.SettingsPath
}

func (m Model) fileRows() string {
	rows := make([]string, len(m.config.SettingsFiles))
	for i, file := range m.config.SettingsFiles {
		rows[i] = m.fileRow(i, file)
	}
	return strings.Join(rows, "\n")
}

func (m Model) fileRow(index int, file settings.File) string {
	pointer, label := "  ", file.Label
	if index == m.pickCursor {
		pointer, label = selectedStyle.Render("› "), selectedStyle.Render(label)
	}
	return pointer + pad(label, labelWidth) + " " + pad(fileMarker(file.Path, m.config.SettingsPath), markerWidth) + " " + file.Path
}

func fileMarker(path, activePath string) string {
	if path == activePath {
		return onStyle.Render("● active")
	}
	if _, err := os.Stat(path); errors.Is(err, fs.ErrNotExist) {
		return mutedStyle.Render("(new)")
	}
	return ""
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

func (m Model) sourceLine() string {
	if m.syncedAt.IsZero() {
		return "Tool list: not synced yet"
	}
	return fmt.Sprintf("Tool list: %s · synced %s · %d tools", m.source, m.syncedAt.Format("2006-01-02 15:04"), len(m.tools))
}

func (m Model) headerLine() string {
	return headerStyle.Render(fmt.Sprintf("  %-*s %-*s %-*s %s", nameWidth, "TOOL", permissionWidth, "PERMISSION", contextWidth, "CONTEXT", "DESCRIPTION"))
}

func (m Model) visibleRowCount(helpView string) int {
	helpLines := strings.Count(helpView, "\n") + 1
	return max(1, m.height-chromeLines-helpLines)
}

func (m Model) toolRows(visible int) string {
	if len(m.tools) == 0 {
		return mutedStyle.Render("  No tools yet. Press u to sync from the docs.")
	}
	offset := scrollOffset(m.cursor, visible, len(m.tools))
	end := min(len(m.tools), offset+visible)
	rows := make([]string, 0, end-offset)
	for i := offset; i < end; i++ {
		rows = append(rows, m.toolRow(i))
	}
	return strings.Join(rows, "\n")
}

func scrollOffset(cursor, visible, total int) int {
	return max(0, min(cursor-visible/2, total-visible))
}

func (m Model) toolRow(index int) string {
	tool := m.tools[index]
	state := m.states[tool.Name]
	pointer, name := "  ", tool.Name
	if index == m.cursor {
		pointer, name = selectedStyle.Render("› "), selectedStyle.Render(name)
	}
	return pointer +
		pad(name, nameWidth) + " " +
		pad(permissionCell(tool, state), permissionWidth) + " " +
		pad(contextCell(state), contextWidth) + " " +
		mutedStyle.Render(m.truncatedDescription(tool))
}

func permissionCell(tool catalog.Tool, state settings.ToolState) string {
	label := state.Permission.String()
	if state.Permission == settings.Default {
		label += defaultBehaviour(tool)
	}
	return permissionLook[state.Permission].Render(label)
}

func defaultBehaviour(tool catalog.Tool) string {
	if tool.PromptsByDefault {
		return " (asks)"
	}
	return " (auto)"
}

func contextCell(state settings.ToolState) string {
	if state.InContext() {
		return onStyle.Render("on")
	}
	return offStyle.Render("off")
}

func (m Model) truncatedDescription(tool catalog.Tool) string {
	room := m.width - 2 - nameWidth - permissionWidth - contextWidth - 3
	if room < 10 {
		return ""
	}
	return ansi.Truncate(tool.Description, room, "…")
}

func pad(text string, width int) string {
	return text + strings.Repeat(" ", max(0, width-lipgloss.Width(text)))
}
