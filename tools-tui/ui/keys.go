package ui

import "charm.land/bubbles/v2/key"

type keyMap struct {
	Up      key.Binding
	Down    key.Binding
	Top     key.Binding
	Bottom  key.Binding
	Cycle   key.Binding
	Allow   key.Binding
	Ask     key.Binding
	Deny    key.Binding
	Reset   key.Binding
	Context key.Binding
	Save    key.Binding
	Sync    key.Binding
	Files   key.Binding
	Select  key.Binding
	Cancel  key.Binding
	Help    key.Binding
	Quit    key.Binding
}

func newKeyMap() keyMap {
	return keyMap{
		Up:      key.NewBinding(key.WithKeys("up", "k"), key.WithHelp("↑/k", "up")),
		Down:    key.NewBinding(key.WithKeys("down", "j"), key.WithHelp("↓/j", "down")),
		Top:     key.NewBinding(key.WithKeys("home", "g"), key.WithHelp("g", "top")),
		Bottom:  key.NewBinding(key.WithKeys("end", "G"), key.WithHelp("G", "bottom")),
		Cycle:   key.NewBinding(key.WithKeys("space", "tab"), key.WithHelp("space", "cycle permission")),
		Allow:   key.NewBinding(key.WithKeys("a"), key.WithHelp("a", "allow")),
		Ask:     key.NewBinding(key.WithKeys("p"), key.WithHelp("p", "ask (prompt)")),
		Deny:    key.NewBinding(key.WithKeys("d"), key.WithHelp("d", "deny")),
		Reset:   key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "default (no rule)")),
		Context: key.NewBinding(key.WithKeys("x"), key.WithHelp("x", "disable/enable")),
		Save:    key.NewBinding(key.WithKeys("w", "ctrl+s"), key.WithHelp("w", "save")),
		Sync:    key.NewBinding(key.WithKeys("u"), key.WithHelp("u", "sync from docs")),
		Files:   key.NewBinding(key.WithKeys("f"), key.WithHelp("f", "switch file")),
		Select:  key.NewBinding(key.WithKeys("enter"), key.WithHelp("enter", "open file")),
		Cancel:  key.NewBinding(key.WithKeys("esc"), key.WithHelp("esc", "cancel")),
		Help:    key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "all keys")),
		Quit:    key.NewBinding(key.WithKeys("q", "ctrl+c"), key.WithHelp("q", "quit")),
	}
}

func (k keyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Allow, k.Ask, k.Deny, k.Reset, k.Context, k.Save, k.Files, k.Help, k.Quit}
}

func (k keyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.Top, k.Bottom},
		{k.Allow, k.Ask, k.Deny, k.Reset, k.Cycle},
		{k.Context, k.Save, k.Sync, k.Files},
		{k.Help, k.Quit},
	}
}

type pickerKeyMap struct{ keyMap }

func (k pickerKeyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Up, k.Down, k.Select, k.Cancel, k.Quit}
}

func (k pickerKeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{k.ShortHelp()}
}
