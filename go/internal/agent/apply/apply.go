package apply

import (
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strings"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

var ErrAppRunning = errors.New("the Ollama app is running its own server; quit it from the menu bar, then rerun")

type Setup struct {
	Path       string
	Agent      launchd.Agent
	ServerEnv  map[string]string
	Reload     func() *exec.Cmd
	StopBrew   func() *exec.Cmd
	BrewLoaded bool
	AppRunning bool
}

func ServerEnv(setup Setup, out io.Writer) error {
	if setup.AppRunning {
		return ErrAppRunning
	}
	current, _, err := launchd.Load(setup.Path)
	if err != nil {
		return fmt.Errorf("reading %s: %w", setup.Path, err)
	}
	env, changed := variables.WithServerEnv(current, setup.ServerEnv)
	if setup.BrewLoaded {
		if err := run(setup.StopBrew(), "stopping brew services ollama"); err != nil {
			return err
		}
		fmt.Fprintf(out, "stopped brew services ollama; the %s agent runs the server now\n", setup.Agent.Label)
	}
	agent := setup.Agent
	agent.Env = env
	if err := launchd.Save(setup.Path, agent); err != nil {
		return fmt.Errorf("saving %s: %w", setup.Path, err)
	}
	if err := run(setup.Reload(), "reloading "+setup.Agent.Label); err != nil {
		return err
	}
	fmt.Fprintf(out, "%s: set %s; reloaded %s\n", setup.Path, describe(changed), setup.Agent.Label)
	return nil
}

func run(command *exec.Cmd, action string) error {
	output, err := command.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %w: %s", action, err, strings.TrimSpace(string(output)))
	}
	return nil
}

func describe(changed []string) string {
	if len(changed) == 0 {
		return "no new values"
	}
	return strings.Join(changed, " ")
}
