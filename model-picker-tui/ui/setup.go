package ui

import (
	"os"
	"os/exec"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/model-picker-tui/profiles"
)

const setupScript = `ollama pull "$1" && ollama create "$2" -f "$3"`

type sideSetupDoneMsg struct {
	err error
}

func setupCommand(side profiles.SideModel) *exec.Cmd {
	cmd := exec.Command("sh", "-c", setupScript, "sh", side.Base, side.Name, side.Modelfile)
	cmd.Stdout = os.Stderr
	return cmd
}

func runSetup(side profiles.SideModel) tea.Cmd {
	return tea.ExecProcess(setupCommand(side), func(err error) tea.Msg {
		return sideSetupDoneMsg{err: err}
	})
}

func setupStatus(msg sideSetupDoneMsg) string {
	if msg.err != nil {
		return "side model setup failed: " + msg.err.Error()
	}
	return "side model ready"
}
