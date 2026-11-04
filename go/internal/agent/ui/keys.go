package ui

import "charm.land/bubbles/v2/key"

type keyMap struct {
	Up     key.Binding
	Down   key.Binding
	Edit   key.Binding
	Unset  key.Binding
	Reset  key.Binding
	Save   key.Binding
	Apply  key.Binding
	Quit   key.Binding
	Commit key.Binding
	Cancel key.Binding
}

type editKeyMap struct {
	keys keyMap
}

func newKeyMap() keyMap {
	return keyMap{
		Up:     key.NewBinding(key.WithKeys("up", "k"), key.WithHelp("↑/k", "up")),
		Down:   key.NewBinding(key.WithKeys("down", "j"), key.WithHelp("↓/j", "down")),
		Edit:   key.NewBinding(key.WithKeys("enter", "e"), key.WithHelp("enter", "edit")),
		Unset:  key.NewBinding(key.WithKeys("x", "delete"), key.WithHelp("x", "unset")),
		Reset:  key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "server.env value")),
		Save:   key.NewBinding(key.WithKeys("w", "ctrl+s"), key.WithHelp("w", "save")),
		Apply:  key.NewBinding(key.WithKeys("a"), key.WithHelp("a", "save + reload")),
		Quit:   key.NewBinding(key.WithKeys("q", "esc", "ctrl+c"), key.WithHelp("q", "quit")),
		Commit: key.NewBinding(key.WithKeys("enter"), key.WithHelp("enter", "keep")),
		Cancel: key.NewBinding(key.WithKeys("esc"), key.WithHelp("esc", "cancel")),
	}
}

func (k keyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Up, k.Down, k.Edit, k.Unset, k.Reset, k.Save, k.Apply, k.Quit}
}

func (k keyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{k.ShortHelp()}
}

func (k editKeyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.keys.Commit, k.keys.Cancel}
}

func (k editKeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{k.ShortHelp()}
}
