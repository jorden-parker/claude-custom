package ui

import (
	"errors"
	"io"
	"os"
	"path/filepath"
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

const embedding = "qwen3-embedding:0.6b"

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
	m, cmd := press(New(configured, profiles.SideModel{}, embedding), "down", "enter")
	chosen, ok := m.Chosen()
	if !ok || chosen.Size != "35b" {
		t.Fatalf("got %+v, %v", chosen, ok)
	}
	if cmd == nil {
		t.Fatal("expected quit after choosing")
	}
}

func TestCursorStaysInBounds(t *testing.T) {
	m, _ := press(New(configured, profiles.SideModel{}, embedding), "up", "enter")
	if chosen, _ := m.Chosen(); chosen.Size != "27b" {
		t.Fatalf("got %+v", chosen)
	}
	m, _ = press(New(configured, side, embedding), "down", "down", "down", "down", "down")
	if !m.onEmbeddingRow() {
		t.Fatalf("cursor %d is past the last row", m.cursor)
	}
}

func TestVimKeysMoveCursor(t *testing.T) {
	m, _ := press(New(configured, profiles.SideModel{}, embedding), "j", "k", "enter")
	if chosen, _ := m.Chosen(); chosen.Size != "27b" {
		t.Fatalf("got %+v", chosen)
	}
}

func TestCancelKeysChooseNothing(t *testing.T) {
	for _, k := range []string{"esc", "q"} {
		m, cmd := press(New(configured, profiles.SideModel{}, embedding), k)
		if _, ok := m.Chosen(); ok {
			t.Fatalf("%s: expected no choice", k)
		}
		if cmd == nil {
			t.Fatalf("%s: expected quit", k)
		}
	}
}

func TestViewListsSizesAndModels(t *testing.T) {
	view := New(configured, profiles.SideModel{}, embedding).View().Content
	for _, want := range []string{"27b", "qwen3.8-27b-cc", "35b", "qwen3.6:35b-mlx"} {
		if !strings.Contains(view, want) {
			t.Fatalf("view missing %q:\n%s", want, view)
		}
	}
}

func TestSideRowOnlyWithSideModel(t *testing.T) {
	if view := New(configured, profiles.SideModel{}, embedding).View().Content; strings.Contains(view, "Set up side model") {
		t.Fatalf("unexpected side row:\n%s", view)
	}
	view := New(configured, side, embedding).View().Content
	for _, want := range []string{"Set up side model", "qwen3:4b", "qwen3-4b-cc"} {
		if !strings.Contains(view, want) {
			t.Fatalf("view missing %q:\n%s", want, view)
		}
	}
}

func TestEnterOnSideRowRunsSetupWithoutChoosing(t *testing.T) {
	m, cmd := press(New(configured, side, embedding), "down", "down", "enter")
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
	updated, _ := New(configured, side, embedding).Update(setupDoneMsg{label: "side model", err: errors.New("pull failed")})
	if view := updated.(Model).View().Content; !strings.Contains(view, "pull failed") {
		t.Fatalf("view missing error:\n%s", view)
	}
	updated, _ = New(configured, side, embedding).Update(setupDoneMsg{label: "side model"})
	if view := updated.(Model).View().Content; !strings.Contains(view, "side model ready") {
		t.Fatalf("view missing success:\n%s", view)
	}
}

func TestSetupCommandPullsAndCreates(t *testing.T) {
	cmd := setupCommand(sideSetup(side), io.Discard)
	if cmd.Stdout != os.Stderr {
		t.Fatal("setup output must go to stderr; stdout carries the chosen size")
	}
	got := cmd.Args
	want := []string{"sh", "-c", sideSetupScript, "sh", "qwen3:4b", "qwen3-4b-cc", "/repo/ollama/side.Modelfile"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q, want %q", got, want)
	}
	if !strings.Contains(sideSetupScript, "ollama pull") || !strings.Contains(sideSetupScript, "ollama create") {
		t.Fatalf("script does not pull and create: %s", sideSetupScript)
	}
}

func TestSetupFailureShowsOllamaError(t *testing.T) {
	fakeOllama(t, "echo 'pulling manifest'; printf '\\033[KError: pull model manifest: file does not exist\\n' >&2; exit 1")
	var output strings.Builder
	cmd := setupCommand(sideSetup(side), &output)
	cmd.Stdout = io.Discard
	msg := setupResult("side model", cmd.Run(), output.String())
	updated, _ := New(configured, side, embedding).Update(msg)
	view := updated.(Model).View().Content
	if !strings.Contains(view, "side model setup failed: pull model manifest: file does not exist") {
		t.Fatalf("view missing ollama error:\n%s", view)
	}
}

func TestSetupFailureWithoutOllamaErrorShowsExitStatus(t *testing.T) {
	fakeOllama(t, "exit 3")
	var output strings.Builder
	cmd := setupCommand(sideSetup(side), &output)
	msg := setupResult("side model", cmd.Run(), output.String())
	if got := setupStatus(msg); got != "side model setup failed: exit status 3" {
		t.Fatalf("got %q", got)
	}
}

func TestEmbeddingRowIsAlwaysLast(t *testing.T) {
	for _, s := range []profiles.SideModel{{}, side} {
		view := New(configured, s, embedding).View().Content
		lines := strings.Split(view, "\n")
		row := -1
		for i, line := range lines {
			if strings.Contains(line, "Set up embedding model") {
				row = i
			}
			if strings.Contains(line, "Set up side model") && row != -1 {
				t.Fatalf("side row after embedding row:\n%s", view)
			}
		}
		if row == -1 || !strings.Contains(lines[row], embedding) {
			t.Fatalf("view missing embedding row:\n%s", view)
		}
	}
}

func TestEnterOnEmbeddingRowPullsWithoutChoosing(t *testing.T) {
	for _, s := range []profiles.SideModel{{}, side} {
		m, _ := press(New(configured, s, embedding), "down", "down", "down")
		if !m.onEmbeddingRow() {
			t.Fatalf("cursor %d is not on the embedding row", m.cursor)
		}
		m, cmd := press(m, "enter")
		if _, ok := m.Chosen(); ok {
			t.Fatal("expected no profile chosen")
		}
		if cmd == nil || !strings.Contains(m.status, "pulling "+embedding) {
			t.Fatalf("expected a pull, status %q", m.status)
		}
		if _, quit := cmd().(tea.QuitMsg); quit {
			t.Fatal("expected the menu to stay open")
		}
	}
}

func TestEmbeddingSetupOnlyPulls(t *testing.T) {
	got := setupCommand(embeddingSetup(embedding), io.Discard).Args
	want := []string{"sh", "-c", `ollama pull "$1"`, "sh", embedding}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestEmbeddingSetupFailureShowsOllamaError(t *testing.T) {
	fakeOllama(t, "printf 'Error: pull model manifest: file does not exist\\n' >&2; exit 1")
	var output strings.Builder
	cmd := setupCommand(embeddingSetup(embedding), &output)
	cmd.Stdout = io.Discard
	msg := setupResult("embedding model", cmd.Run(), output.String())
	if got := setupStatus(msg); got != "embedding model setup failed: pull model manifest: file does not exist" {
		t.Fatalf("got %q", got)
	}
}

func fakeOllama(t *testing.T, body string) {
	t.Helper()
	dir := t.TempDir()
	script := "#!/bin/sh\n" + body + "\n"
	if err := os.WriteFile(filepath.Join(dir, "ollama"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}
