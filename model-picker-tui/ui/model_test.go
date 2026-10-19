package ui

import (
	"errors"
	"os"
	"reflect"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/model-picker-tui/profiles"
)

var configured = []profiles.Profile{
	{Size: "27b", Model: "qwen3.8-27b-cc", Base: "qwen3.8:27b-mlx"},
	{Size: "35b", Model: "qwen3.6-35b-cc", Base: "qwen3.6:35b-mlx"},
}

var side = profiles.SideModel{Name: "qwen3-4b-cc", Base: "qwen3:4b", Modelfile: "/repo/ollama/side.Modelfile"}

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
	m, cmd := press(New(configured, profiles.SideModel{}), "down", "enter")
	chosen, ok := m.Chosen()
	if !ok || chosen.Size != "35b" {
		t.Fatalf("got %+v, %v", chosen, ok)
	}
	if cmd == nil {
		t.Fatal("expected quit after choosing")
	}
}

func TestCursorStaysInBounds(t *testing.T) {
	m, _ := press(New(configured, profiles.SideModel{}), "up", "down", "down", "down", "enter")
	if chosen, _ := m.Chosen(); chosen.Size != "35b" {
		t.Fatalf("got %+v", chosen)
	}
}

func TestVimKeysMoveCursor(t *testing.T) {
	m, _ := press(New(configured, profiles.SideModel{}), "j", "k", "enter")
	if chosen, _ := m.Chosen(); chosen.Size != "27b" {
		t.Fatalf("got %+v", chosen)
	}
}

func TestCancelKeysChooseNothing(t *testing.T) {
	for _, k := range []string{"esc", "q"} {
		m, cmd := press(New(configured, profiles.SideModel{}), k)
		if _, ok := m.Chosen(); ok {
			t.Fatalf("%s: expected no choice", k)
		}
		if cmd == nil {
			t.Fatalf("%s: expected quit", k)
		}
	}
}

func TestViewListsSizesAndModels(t *testing.T) {
	view := New(configured, profiles.SideModel{}).View().Content
	for _, want := range []string{"27b", "qwen3.8-27b-cc", "35b", "qwen3.6:35b-mlx"} {
		if !strings.Contains(view, want) {
			t.Fatalf("view missing %q:\n%s", want, view)
		}
	}
}

func TestSideRowOnlyWithSideModel(t *testing.T) {
	if view := New(configured, profiles.SideModel{}).View().Content; strings.Contains(view, "Set up side model") {
		t.Fatalf("unexpected side row:\n%s", view)
	}
	view := New(configured, side).View().Content
	for _, want := range []string{"Set up side model", "qwen3:4b", "qwen3-4b-cc"} {
		if !strings.Contains(view, want) {
			t.Fatalf("view missing %q:\n%s", want, view)
		}
	}
}

func TestEnterOnSideRowRunsSetupWithoutChoosing(t *testing.T) {
	m, cmd := press(New(configured, side), "down", "down", "enter")
	if _, ok := m.Chosen(); ok {
		t.Fatal("expected no profile chosen")
	}
	if cmd == nil {
		t.Fatal("expected a setup command")
	}
	if _, quit := cmd().(tea.QuitMsg); quit {
		t.Fatal("expected the menu to stay open")
	}
}

func TestSetupResultShowsInView(t *testing.T) {
	updated, _ := New(configured, side).Update(sideSetupDoneMsg{err: errors.New("pull failed")})
	if view := updated.(Model).View().Content; !strings.Contains(view, "pull failed") {
		t.Fatalf("view missing error:\n%s", view)
	}
	updated, _ = New(configured, side).Update(sideSetupDoneMsg{})
	if view := updated.(Model).View().Content; !strings.Contains(view, "side model ready") {
		t.Fatalf("view missing success:\n%s", view)
	}
}

func TestSetupCommandPullsAndCreates(t *testing.T) {
	cmd := setupCommand(side)
	if cmd.Stdout != os.Stderr {
		t.Fatal("setup output must go to stderr; stdout carries the chosen size")
	}
	got := cmd.Args
	want := []string{"sh", "-c", setupScript, "sh", "qwen3:4b", "qwen3-4b-cc", "/repo/ollama/side.Modelfile"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q, want %q", got, want)
	}
	if !strings.Contains(setupScript, "ollama pull") || !strings.Contains(setupScript, "ollama create") {
		t.Fatalf("script does not pull and create: %s", setupScript)
	}
}
