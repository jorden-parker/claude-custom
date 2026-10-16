package ui

import (
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/model-picker-tui/profiles"
)

var configured = []profiles.Profile{
	{Size: "27b", Model: "qwen3.8-27b-cc", Base: "qwen3.8:27b-mlx"},
	{Size: "35b", Model: "qwen3.6-35b-cc", Base: "qwen3.6:35b-mlx"},
}

func press(m Model, keys ...string) (Model, tea.Cmd) {
	var cmd tea.Cmd
	for _, k := range keys {
		var msg tea.KeyPressMsg
		switch k {
		case "down":
			msg = tea.KeyPressMsg{Code: tea.KeyDown}
		case "up":
			msg = tea.KeyPressMsg{Code: tea.KeyUp}
		case "enter":
			msg = tea.KeyPressMsg{Code: tea.KeyEnter}
		case "esc":
			msg = tea.KeyPressMsg{Code: tea.KeyEscape}
		default:
			msg = tea.KeyPressMsg{Code: rune(k[0]), Text: k}
		}
		updated, next := m.Update(msg)
		m, cmd = updated.(Model), next
	}
	return m, cmd
}

func TestEnterChoosesHighlightedProfile(t *testing.T) {
	m, cmd := press(New(configured), "down", "enter")
	chosen, ok := m.Chosen()
	if !ok || chosen.Size != "35b" {
		t.Fatalf("got %+v, %v", chosen, ok)
	}
	if cmd == nil {
		t.Fatal("expected quit after choosing")
	}
}

func TestCursorStaysInBounds(t *testing.T) {
	m, _ := press(New(configured), "up", "down", "down", "down", "enter")
	if chosen, _ := m.Chosen(); chosen.Size != "35b" {
		t.Fatalf("got %+v", chosen)
	}
}

func TestVimKeysMoveCursor(t *testing.T) {
	m, _ := press(New(configured), "j", "k", "enter")
	if chosen, _ := m.Chosen(); chosen.Size != "27b" {
		t.Fatalf("got %+v", chosen)
	}
}

func TestCancelKeysChooseNothing(t *testing.T) {
	for _, k := range []string{"esc", "q"} {
		m, cmd := press(New(configured), k)
		if _, ok := m.Chosen(); ok {
			t.Fatalf("%s: expected no choice", k)
		}
		if cmd == nil {
			t.Fatalf("%s: expected quit", k)
		}
	}
}

func TestViewListsSizesAndModels(t *testing.T) {
	view := New(configured).View().Content
	for _, want := range []string{"27b", "qwen3.8-27b-cc", "35b", "qwen3.6:35b-mlx"} {
		if !strings.Contains(view, want) {
			t.Fatalf("view missing %q:\n%s", want, view)
		}
	}
}
