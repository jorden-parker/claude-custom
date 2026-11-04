package ui

import (
	"fmt"
	"maps"
	"os/exec"
	"strings"

	"charm.land/bubbles/v2/help"
	"charm.land/bubbles/v2/key"
	"charm.land/bubbles/v2/textinput"
	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

type Config struct {
	Agent     launchd.Agent
	Path      string
	ServerEnv map[string]string
	Reload    func() *exec.Cmd
	Conflicts []string
}

type Model struct {
	config         Config
	names          []string
	values         map[string]string
	saved          map[string]string
	cursor         int
	editing        bool
	input          textinput.Model
	confirmingQuit bool
	status         string
	width          int
	keys           keyMap
	help           help.Model
}

type reloadedMsg struct {
	err    error
	output string
}

func New(config Config) (Model, error) {
	onDisk, found, err := launchd.Load(config.Path)
	if err != nil {
		return Model{}, fmt.Errorf("reading %s: %w", config.Path, err)
	}
	m := Model{
		config: config,
		names:  variables.Names(onDisk, config.ServerEnv),
		values: maps.Clone(onDisk),
		saved:  onDisk,
		input:  textinput.New(),
		keys:   newKeyMap(),
		help:   help.New(),
	}
	if !found {
		m.values = maps.Clone(config.ServerEnv)
		m.status = "No agent yet; values come from server.env. Press w to create it."
	}
	return m, nil
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.help.SetWidth(msg.Width)
		return m, nil
	case reloadedMsg:
		m.status = reloadStatus(m.config.Agent.Label, msg)
		return m, nil
	case tea.KeyPressMsg:
		if m.editing {
			return m.handleEditKey(msg)
		}
		return m.handleKey(msg)
	}
	if m.editing {
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(msg)
		return m, cmd
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if key.Matches(msg, m.keys.Quit) {
		return m.quit()
	}
	m.confirmingQuit = false
	switch {
	case key.Matches(msg, m.keys.Up):
		m.moveCursor(-1)
	case key.Matches(msg, m.keys.Down):
		m.moveCursor(1)
	case key.Matches(msg, m.keys.Edit):
		return m.startEdit()
	case key.Matches(msg, m.keys.Unset):
		delete(m.values, m.selected())
	case key.Matches(msg, m.keys.Reset):
		m.resetSelected()
	case key.Matches(msg, m.keys.Save):
		m.save()
	case key.Matches(msg, m.keys.Apply):
		return m.apply()
	}
	return m, nil
}

func (m Model) handleEditKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Commit):
		m.setSelected(strings.TrimSpace(m.input.Value()))
		m.stopEdit()
	case key.Matches(msg, m.keys.Cancel):
		m.stopEdit()
	default:
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(msg)
		return m, cmd
	}
	return m, nil
}

func (m Model) startEdit() (tea.Model, tea.Cmd) {
	m.editing = true
	m.input.SetValue(m.values[m.selected()])
	m.input.CursorEnd()
	return m, m.input.Focus()
}

func (m *Model) stopEdit() {
	m.editing = false
	m.input.Blur()
}

func (m *Model) setSelected(value string) {
	if value == "" {
		delete(m.values, m.selected())
		return
	}
	m.values[m.selected()] = value
}

func (m *Model) resetSelected() {
	m.setSelected(m.config.ServerEnv[m.selected()])
}

func (m Model) selected() string {
	return m.names[m.cursor]
}

func (m *Model) moveCursor(delta int) {
	m.cursor = max(0, min(len(m.names)-1, m.cursor+delta))
}

func (m Model) dirty() bool {
	return !maps.Equal(m.values, m.saved)
}

func (m Model) quit() (tea.Model, tea.Cmd) {
	if !m.dirty() || m.confirmingQuit {
		return m, tea.Quit
	}
	m.confirmingQuit = true
	m.status = "Unsaved changes. Press w to save, or q again to quit without saving."
	return m, nil
}

func (m *Model) save() bool {
	agent := m.config.Agent
	agent.Env = maps.Clone(m.values)
	if err := launchd.Save(m.config.Path, agent); err != nil {
		m.status = "Save failed: " + err.Error()
		return false
	}
	m.saved = maps.Clone(m.values)
	m.status = "Saved " + m.config.Path
	return true
}

func (m Model) apply() (tea.Model, tea.Cmd) {
	if !m.save() {
		return m, nil
	}
	m.status = "Reloading " + m.config.Agent.Label + "…"
	return m, reload(m.config.Reload())
}

func reload(command *exec.Cmd) tea.Cmd {
	return func() tea.Msg {
		output, err := command.CombinedOutput()
		return reloadedMsg{err: err, output: strings.TrimSpace(string(output))}
	}
}

func reloadStatus(label string, msg reloadedMsg) string {
	switch {
	case msg.err == nil:
		return "Saved and reloaded " + label
	case msg.output != "":
		return "Reload failed: " + msg.output
	default:
		return "Reload failed: " + msg.err.Error()
	}
}
