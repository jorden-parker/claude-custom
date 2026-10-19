package ui

import (
	"charm.land/bubbles/v2/help"
	"charm.land/bubbles/v2/key"
	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/picker/profiles"
)

type Model struct {
	profiles  []profiles.Profile
	side      profiles.SideModel
	embedding string
	cursor    int
	chosen    bool
	status    string
	keys      keyMap
	help      help.Model
}

func New(configured []profiles.Profile, side profiles.SideModel, embedding string) Model {
	return Model{profiles: configured, side: side, embedding: embedding, keys: newKeyMap(), help: help.New()}
}

func (m Model) Chosen() (profiles.Profile, bool) {
	if !m.chosen {
		return profiles.Profile{}, false
	}
	return m.profiles[m.cursor], true
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.help.SetWidth(msg.Width)
	case tea.KeyPressMsg:
		return m.handleKey(msg)
	case setupDoneMsg:
		m.status = setupStatus(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Up):
		m.cursor = max(m.cursor-1, 0)
	case key.Matches(msg, m.keys.Down):
		m.cursor = min(m.cursor+1, m.rowCount()-1)
	case key.Matches(msg, m.keys.Select):
		return m.selectRow()
	case key.Matches(msg, m.keys.Cancel):
		return m, tea.Quit
	}
	return m, nil
}

func (m Model) selectRow() (tea.Model, tea.Cmd) {
	if m.onSideRow() {
		m.status = "setting up " + m.side.Name + "…"
		return m, runSetup(sideSetup(m.side))
	}
	if m.onEmbeddingRow() {
		m.status = "pulling " + m.embedding + "…"
		return m, runSetup(embeddingSetup(m.embedding))
	}
	m.chosen = true
	return m, tea.Quit
}

func (m Model) rowCount() int {
	return m.embeddingRowIndex() + 1
}

func (m Model) embeddingRowIndex() int {
	if m.side.Configured() {
		return len(m.profiles) + 1
	}
	return len(m.profiles)
}

func (m Model) onSideRow() bool {
	return m.side.Configured() && m.cursor == len(m.profiles)
}

func (m Model) onEmbeddingRow() bool {
	return m.cursor == m.embeddingRowIndex()
}
