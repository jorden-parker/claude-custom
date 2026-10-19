package ui

import (
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/picker/profiles"
)

const (
	sideSetupScript      = `ollama pull "$1" && ollama create "$2" -f "$3"`
	embeddingSetupScript = `ollama pull "$1"`
	ollamaErrorPrefix    = "Error: "
)

var terminalEscape = regexp.MustCompile(`\x1b\[[0-9;?]*[A-Za-z]`)

type setupTask struct {
	label  string
	script string
	args   []string
}

type setupDoneMsg struct {
	label       string
	err         error
	ollamaError string
}

func sideSetup(side profiles.SideModel) setupTask {
	return setupTask{label: "side model", script: sideSetupScript, args: []string{side.Base, side.Name, side.Modelfile}}
}

func embeddingSetup(name string) setupTask {
	return setupTask{label: "embedding model", script: embeddingSetupScript, args: []string{name}}
}

func setupCommand(task setupTask, errorOutput io.Writer) *exec.Cmd {
	cmd := exec.Command("sh", append([]string{"-c", task.script, "sh"}, task.args...)...)
	cmd.Stdout = os.Stderr
	cmd.Stderr = io.MultiWriter(os.Stderr, errorOutput)
	return cmd
}

func runSetup(task setupTask) tea.Cmd {
	var errorOutput strings.Builder
	return tea.ExecProcess(setupCommand(task, &errorOutput), func(err error) tea.Msg {
		return setupResult(task.label, err, errorOutput.String())
	})
}

func setupResult(label string, err error, errorOutput string) setupDoneMsg {
	if err == nil {
		return setupDoneMsg{label: label}
	}
	return setupDoneMsg{label: label, err: err, ollamaError: lastOllamaError(errorOutput)}
}

func lastOllamaError(output string) string {
	lines := strings.FieldsFunc(terminalEscape.ReplaceAllString(output, ""), func(r rune) bool {
		return r == '\n' || r == '\r'
	})
	for i := len(lines) - 1; i >= 0; i-- {
		if message, ok := strings.CutPrefix(strings.TrimSpace(lines[i]), ollamaErrorPrefix); ok {
			return message
		}
	}
	return ""
}

func setupStatus(msg setupDoneMsg) string {
	switch {
	case msg.err == nil:
		return msg.label + " ready"
	case msg.ollamaError != "":
		return msg.label + " setup failed: " + msg.ollamaError
	default:
		return msg.label + " setup failed: " + msg.err.Error()
	}
}
