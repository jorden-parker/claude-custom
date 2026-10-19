package ui

import (
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/model-picker-tui/profiles"
)

const (
	setupScript       = `ollama pull "$1" && ollama create "$2" -f "$3"`
	ollamaErrorPrefix = "Error: "
)

var terminalEscape = regexp.MustCompile(`\x1b\[[0-9;?]*[A-Za-z]`)

type sideSetupDoneMsg struct {
	err         error
	ollamaError string
}

func setupCommand(side profiles.SideModel, errorOutput io.Writer) *exec.Cmd {
	cmd := exec.Command("sh", "-c", setupScript, "sh", side.Base, side.Name, side.Modelfile)
	cmd.Stdout = os.Stderr
	cmd.Stderr = io.MultiWriter(os.Stderr, errorOutput)
	return cmd
}

func runSetup(side profiles.SideModel) tea.Cmd {
	var errorOutput strings.Builder
	return tea.ExecProcess(setupCommand(side, &errorOutput), func(err error) tea.Msg {
		return setupResult(err, errorOutput.String())
	})
}

func setupResult(err error, errorOutput string) sideSetupDoneMsg {
	if err == nil {
		return sideSetupDoneMsg{}
	}
	return sideSetupDoneMsg{err: err, ollamaError: lastOllamaError(errorOutput)}
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

func setupStatus(msg sideSetupDoneMsg) string {
	switch {
	case msg.err == nil:
		return "side model ready"
	case msg.ollamaError != "":
		return "side model setup failed: " + msg.ollamaError
	default:
		return "side model setup failed: " + msg.err.Error()
	}
}
