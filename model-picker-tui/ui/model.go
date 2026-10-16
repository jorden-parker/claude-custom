package ui

import (
	"charm.land/bubbles/v2/help"
	"charm.land/bubbles/v2/key"
	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/model-picker-tui/profiles"
)

type Model struct {
	profiles []profiles.Profile
	cursor   int
	chosen   bool
	keys     keyMap
	help     help.Model
}

func New(configured []profiles.Profile) Model {
	return Model{profiles: configured, keys: newKeyMap(), help: help.New()}
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
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Up):
		m.cursor = max(m.cursor-1, 0)
	case key.Matches(msg, m.keys.Down):
		m.cursor = min(m.cursor+1, len(m.profiles)-1)
	case key.Matches(msg, m.keys.Select):
		m.chosen = true
		return m, tea.Quit
	case key.Matches(msg, m.keys.Cancel):
		return m, tea.Quit
	}
	return m, nil
}
