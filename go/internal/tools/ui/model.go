package ui

import (
	"fmt"
	"maps"
	"slices"
	"strings"
	"time"

	"charm.land/bubbles/v2/help"
	"charm.land/bubbles/v2/key"
	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/tools/catalog"
	"github.com/jordenparker/claude-custom/go/internal/tools/settings"
)

type Config struct {
	SettingsPath  string
	SettingsFiles []settings.File
	SnapshotPath  string
	DocsURL       string
}

type Model struct {
	config         Config
	tools          []catalog.Tool
	source         string
	syncedAt       time.Time
	states         map[string]settings.ToolState
	saved          map[string]settings.ToolState
	cursor         int
	width          int
	height         int
	status         string
	confirmingQuit bool
	picking        bool
	pickCursor     int
	confirmSwitch  bool
	keys           keyMap
	help           help.Model
}

type syncedMsg struct {
	snapshot catalog.Snapshot
	err      error
}

func New(config Config) (Model, error) {
	m := Model{config: config, keys: newKeyMap(), help: help.New()}
	if snapshot, err := catalog.LoadSnapshot(config.SnapshotPath); err == nil {
		m.tools, m.source, m.syncedAt = snapshot.Tools, snapshot.Source, snapshot.SyncedAt
	}
	states, err := m.statesOnDisk()
	if err != nil {
		return m, err
	}
	m.states, m.saved = states, maps.Clone(states)
	return m, nil
}

func (m Model) Init() tea.Cmd {
	if len(m.tools) == 0 {
		return m.startSync()
	}
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.help.SetWidth(msg.Width)
	case syncedMsg:
		return m.applySync(msg), nil
	case tea.KeyPressMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if key.Matches(msg, m.keys.Quit) {
		return m.quit()
	}
	m.confirmingQuit = false
	if m.picking {
		return m.handlePickerKey(msg), nil
	}
	switch {
	case key.Matches(msg, m.keys.Up):
		m.moveCursor(-1)
	case key.Matches(msg, m.keys.Down):
		m.moveCursor(1)
	case key.Matches(msg, m.keys.Top):
		m.moveCursor(-len(m.tools))
	case key.Matches(msg, m.keys.Bottom):
		m.moveCursor(len(m.tools))
	case key.Matches(msg, m.keys.Allow):
		m.setPermission(settings.Allow)
	case key.Matches(msg, m.keys.Ask):
		m.setPermission(settings.Ask)
	case key.Matches(msg, m.keys.Deny):
		m.setPermission(settings.Deny)
	case key.Matches(msg, m.keys.Reset):
		m.setPermission(settings.Default)
	case key.Matches(msg, m.keys.Cycle):
		m.updateSelected(settings.ToolState.NextPermission)
	case key.Matches(msg, m.keys.Context):
		m.updateSelected(settings.ToolState.ToggledContext)
	case key.Matches(msg, m.keys.Save):
		m.save()
	case key.Matches(msg, m.keys.Sync):
		return m, m.startSync()
	case key.Matches(msg, m.keys.Files):
		m.openPicker()
	case key.Matches(msg, m.keys.Help):
		m.help.ShowAll = !m.help.ShowAll
	}
	return m, nil
}

func (m Model) handlePickerKey(msg tea.KeyPressMsg) Model {
	switch {
	case key.Matches(msg, m.keys.Up):
		m.movePickCursor(-1)
	case key.Matches(msg, m.keys.Down):
		m.movePickCursor(1)
	case key.Matches(msg, m.keys.Cancel):
		m.closePicker()
	case key.Matches(msg, m.keys.Select):
		m.chooseFile()
	}
	return m
}

func (m *Model) openPicker() {
	if len(m.config.SettingsFiles) < 2 {
		m.status = "No other settings files found."
		return
	}
	m.picking = true
	m.pickCursor = max(0, m.activeFileIndex())
}

func (m *Model) closePicker() {
	m.picking, m.confirmSwitch = false, false
}

func (m *Model) movePickCursor(delta int) {
	m.pickCursor = max(0, min(len(m.config.SettingsFiles)-1, m.pickCursor+delta))
	m.confirmSwitch = false
}

func (m *Model) chooseFile() {
	file := m.config.SettingsFiles[m.pickCursor]
	switch {
	case file.Path == m.config.SettingsPath:
		m.closePicker()
	case m.dirty() && !m.confirmSwitch:
		m.confirmSwitch = true
		m.status = "Unsaved changes. Press enter again to discard them, or esc then w to save."
	default:
		m.switchTo(file)
	}
}

func (m *Model) switchTo(file settings.File) {
	states, err := m.statesIn(file.Path)
	if err != nil {
		m.confirmSwitch = false
		m.status = "Could not open " + file.Path + ": " + err.Error()
		return
	}
	m.config.SettingsPath = file.Path
	m.states, m.saved = states, maps.Clone(states)
	m.closePicker()
	m.status = "Editing " + file.Label + " " + file.Path
}

func (m Model) activeFileIndex() int {
	return slices.IndexFunc(m.config.SettingsFiles, func(f settings.File) bool { return f.Path == m.config.SettingsPath })
}

func (m Model) quit() (tea.Model, tea.Cmd) {
	if !m.dirty() || m.confirmingQuit {
		return m, tea.Quit
	}
	m.confirmingQuit = true
	m.status = "Unsaved changes. Press w to save, or q again to quit without saving."
	return m, nil
}

func (m *Model) moveCursor(delta int) {
	m.cursor = max(0, min(len(m.tools)-1, m.cursor+delta))
}

func (m *Model) setPermission(p settings.Permission) {
	m.updateSelected(func(s settings.ToolState) settings.ToolState { return s.WithPermission(p) })
}

func (m *Model) updateSelected(change func(settings.ToolState) settings.ToolState) {
	if len(m.tools) == 0 {
		return
	}
	name := m.tools[m.cursor].Name
	m.states[name] = change(m.states[name])
	m.status = ""
}

func (m Model) dirty() bool {
	return !maps.Equal(m.states, m.saved)
}

func (m *Model) save() {
	data, err := settings.Load(m.config.SettingsPath)
	if err == nil {
		data, err = settings.Write(data, m.states)
	}
	if err == nil {
		err = settings.Save(m.config.SettingsPath, data)
	}
	if err != nil {
		m.status = "Save failed: " + err.Error()
		return
	}
	m.saved = maps.Clone(m.states)
	m.status = "Saved " + m.config.SettingsPath
}

func (m *Model) startSync() tea.Cmd {
	m.status = "Syncing tool list from " + m.config.DocsURL + " …"
	url, snapshotPath := m.config.DocsURL, m.config.SnapshotPath
	return func() tea.Msg {
		tools, err := catalog.Fetch(url)
		if err != nil {
			return syncedMsg{err: err}
		}
		snapshot := catalog.Snapshot{Source: url, SyncedAt: time.Now(), Tools: tools}
		return syncedMsg{snapshot: snapshot, err: catalog.SaveSnapshot(snapshotPath, snapshot)}
	}
}

func (m Model) applySync(msg syncedMsg) Model {
	if msg.err != nil {
		m.status = "Sync failed, keeping the cached list: " + msg.err.Error()
		return m
	}
	added, dropped := catalog.Diff(m.tools, msg.snapshot.Tools)
	if len(m.tools) == 0 {
		added = nil
	}
	m.tools, m.source, m.syncedAt = msg.snapshot.Tools, msg.snapshot.Source, msg.snapshot.SyncedAt
	onDisk, err := m.statesOnDisk()
	if err != nil {
		m.status = "Synced, but the settings file could not be read: " + err.Error()
		return m
	}
	m.states = mergeUnsaved(onDisk, m.states, m.saved)
	m.saved = onDisk
	m.moveCursor(0)
	m.status = syncSummary(len(m.tools), added, dropped)
	return m
}

func mergeUnsaved(onDisk, current, saved map[string]settings.ToolState) map[string]settings.ToolState {
	merged := maps.Clone(onDisk)
	for name := range merged {
		if state, known := current[name]; known && state != saved[name] {
			merged[name] = state
		}
	}
	return merged
}

func syncSummary(total int, added, dropped []string) string {
	summary := fmt.Sprintf("Synced %d tools.", total)
	if len(added) > 0 {
		summary += " Added: " + strings.Join(added, ", ") + "."
	}
	if len(dropped) > 0 {
		summary += " Dropped: " + strings.Join(dropped, ", ") + "."
	}
	return summary
}

func (m Model) statesOnDisk() (map[string]settings.ToolState, error) {
	return m.statesIn(m.config.SettingsPath)
}

func (m Model) statesIn(path string) (map[string]settings.ToolState, error) {
	data, err := settings.Load(path)
	if err != nil {
		return nil, err
	}
	names := make([]string, len(m.tools))
	for i, tool := range m.tools {
		names[i] = tool.Name
	}
	return settings.Read(data, names)
}
