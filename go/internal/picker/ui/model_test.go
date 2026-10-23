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
	"github.com/charmbracelet/x/ansi"

	"github.com/jordenparker/claude-custom/go/internal/picker/profiles"
)

var configured = []profiles.Profile{
	{Size: "27b", Model: "qwen3.8-27b-cc", Base: "qwen3.8:27b-mlx"},
	{Size: "35b", Model: "qwen3.6-35b-cc", Base: "qwen3.6:35b-mlx"},
}

const embedding = "qwen3-embedding:0.6b"

var longSize = profiles.Profile{Size: "gemma-12b-agentic", Model: "gemma-4-12b-agentic-cc", Base: "hf.co/example/gemma-4-12B-agentic-GGUF:Q4_K_M"}

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
	m, cmd := press(New(configured, embedding), "down", "enter")
	chosen, ok := m.Chosen()
	if !ok || chosen.Size != "35b" {
		t.Fatalf("got %+v, %v", chosen, ok)
	}
	if cmd == nil {
		t.Fatal("expected quit after choosing")
	}
}

func TestCursorStaysInBounds(t *testing.T) {
	m, _ := press(New(configured, embedding), "up", "enter")
	if chosen, _ := m.Chosen(); chosen.Size != "27b" {
		t.Fatalf("got %+v", chosen)
	}
	m, _ = press(New(configured, embedding), "down", "down", "down", "down", "down")
	if !m.onEmbeddingRow() {
		t.Fatalf("cursor %d is past the last row", m.cursor)
	}
}

func TestVimKeysMoveCursor(t *testing.T) {
	m, _ := press(New(configured, embedding), "j", "k", "enter")
	if chosen, _ := m.Chosen(); chosen.Size != "27b" {
		t.Fatalf("got %+v", chosen)
	}
}

func TestCancelKeysChooseNothing(t *testing.T) {
	for _, k := range []string{"esc", "q"} {
		m, cmd := press(New(configured, embedding), k)
		if _, ok := m.Chosen(); ok {
			t.Fatalf("%s: expected no choice", k)
		}
		if cmd == nil {
			t.Fatalf("%s: expected quit", k)
		}
	}
}

func TestViewListsSizesAndModels(t *testing.T) {
	view := New(configured, embedding).View().Content
	for _, want := range []string{"27b", "qwen3.8-27b-cc", "35b", "qwen3.6:35b-mlx"} {
		if !strings.Contains(view, want) {
			t.Fatalf("view missing %q:\n%s", want, view)
		}
	}
}

func TestViewUsesAltScreen(t *testing.T) {
	if !New(configured, embedding).View().AltScreen {
		t.Fatal("inline rendering leaves a copy of the menu behind after each setup run")
	}
}

func TestViewHasNoSideModelRow(t *testing.T) {
	if view := New(configured, embedding).View().Content; strings.Contains(view, "side model") {
		t.Fatalf("unexpected side model row:\n%s", view)
	}
}

func TestEmbeddingSetupResultShowsInView(t *testing.T) {
	updated, _ := New(configured, embedding).Update(setupDoneMsg{label: "embedding model", err: errors.New("pull failed")})
	if view := updated.(Model).View().Content; !strings.Contains(view, "pull failed") {
		t.Fatalf("view missing error:\n%s", view)
	}
	updated, _ = New(configured, embedding).Update(setupDoneMsg{label: "embedding model"})
	if view := updated.(Model).View().Content; !strings.Contains(view, "embedding model ready") {
		t.Fatalf("view missing success:\n%s", view)
	}
}

func TestEmbeddingSetupCommandSendsOutputToStderr(t *testing.T) {
	cmd := setupCommand(embeddingSetup(embedding), io.Discard)
	if cmd.Stdout != os.Stderr {
		t.Fatal("setup output must go to stderr; stdout carries the chosen size")
	}
}

func TestEnterOnEmbeddingRowPullsWithoutChoosing(t *testing.T) {
	m, _ := press(New(configured, embedding), "down", "down")
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

func TestEmbeddingSetupFailureWithoutOllamaErrorShowsExitStatus(t *testing.T) {
	fakeOllama(t, "exit 3")
	var output strings.Builder
	cmd := setupCommand(embeddingSetup(embedding), &output)
	msg := setupResult("embedding model", cmd.Run(), output.String())
	if got := setupStatus(msg); got != "embedding model setup failed: exit status 3" {
		t.Fatalf("got %q", got)
	}
}

func TestEmbeddingRowIsAlwaysLast(t *testing.T) {
	view := New(configured, embedding).View().Content
	lines := strings.Split(view, "\n")
	row := -1
	for i, line := range lines {
		if strings.Contains(line, "Set up embedding model") {
			row = i
		}
	}
	if row == -1 || !strings.Contains(lines[row], embedding) {
		t.Fatalf("view missing embedding row:\n%s", view)
	}
}

func TestLongSizeStaysOnOneLine(t *testing.T) {
	view := New(append([]profiles.Profile{longSize}, configured...), embedding).View().Content
	var rows []string
	for _, line := range strings.Split(ansi.Strip(view), "\n") {
		if strings.Contains(line, "gemma-12b-agentic") {
			rows = append(rows, line)
		}
	}
	if len(rows) != 1 || !strings.Contains(rows[0], "gemma-4-12b-agentic-cc") {
		t.Fatalf("long size not on one line with its model:\n%s", view)
	}
}

func TestDetailsShareOneColumn(t *testing.T) {
	details := []string{"gemma-4-12b-agentic-cc", "qwen3.8-27b-cc", "qwen3.6-35b-cc", "qwen3-embedding:0.6b"}
	fresh := New(append([]profiles.Profile{longSize}, configured...), embedding)
	moved, _ := press(fresh, "down")
	for _, m := range []Model{fresh, moved} {
		assertDetailsShareColumn(t, m.View().Content, details)
	}
}

func TestRowsFitTerminalWidth(t *testing.T) {
	updated, _ := New(append([]profiles.Profile{longSize}, configured...), embedding).Update(tea.WindowSizeMsg{Width: 60, Height: 20})
	view := updated.(Model).View().Content
	for _, line := range strings.Split(view, "\n") {
		if width := ansi.StringWidth(line); width > 60 {
			t.Fatalf("line is %d cells wide, want at most 60: %q\n%s", width, ansi.Strip(line), ansi.Strip(view))
		}
	}
	for _, line := range strings.Split(ansi.Strip(view), "\n") {
		if strings.Contains(line, "gemma-12b-agentic") && !strings.HasSuffix(strings.TrimRight(line, " "), "…") {
			t.Fatalf("long row not truncated with an ellipsis: %q", line)
		}
	}
}

func assertDetailsShareColumn(t *testing.T, view string, details []string) {
	t.Helper()
	lines := strings.Split(ansi.Strip(view), "\n")
	column := -1
	for _, want := range details {
		index := -1
		for _, line := range lines {
			if at := strings.Index(line, want); at != -1 {
				index = at
			}
		}
		if index == -1 {
			t.Fatalf("view missing %q:\n%s", want, view)
		}
		if column == -1 {
			column = index
		}
		if index != column {
			t.Fatalf("%q starts at column %d, want %d:\n%s", want, index, column, view)
		}
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
