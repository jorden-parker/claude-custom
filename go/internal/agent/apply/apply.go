package apply

import (
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"

	"github.com/jordenparker/claude-custom/go/internal/agent/launchd"
	"github.com/jordenparker/claude-custom/go/internal/agent/variables"
)

const defaultModelsMax = "2"

var ErrNoServer = errors.New("llama-server not found; run brew install llama.cpp, or pass -llama-server")

type Setup struct {
	Path          string
	Server        launchd.Server
	Recommended   map[string]string
	OverridesPath string
	Render        func() *exec.Cmd
	Reload        func() *exec.Cmd
	StopBrew      func() *exec.Cmd
	BrewLoaded    bool
}

func (setup Setup) Values() (map[string]string, error) {
	overrides, err := variables.Load(setup.OverridesPath)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", setup.OverridesPath, err)
	}
	return variables.Effective(setup.Recommended, overrides), nil
}

func (setup Setup) server(values map[string]string) launchd.Server {
	server := setup.Server
	server.ModelsMax = values[variables.ModelsMax]
	if server.ModelsMax == "" {
		server.ModelsMax = defaultModelsMax
	}
	return server
}

func Save(setup Setup, values map[string]string) (bool, error) {
	if setup.Server.Program == "" {
		return false, ErrNoServer
	}
	if err := variables.Save(setup.OverridesPath, variables.Overrides(setup.Recommended, values)); err != nil {
		return false, fmt.Errorf("saving %s: %w", setup.OverridesPath, err)
	}
	if err := run(setup.Render(), "rendering the user presets"); err != nil {
		return false, err
	}
	if err := os.MkdirAll(filepath.Dir(setup.Server.LogFile), 0o700); err != nil {
		return false, err
	}
	written, err := launchd.Save(setup.Path, setup.server(values).Agent())
	if err != nil {
		return false, fmt.Errorf("saving %s: %w", setup.Path, err)
	}
	return written, nil
}

func Agent(setup Setup, out io.Writer) error {
	values, err := setup.Values()
	if err != nil {
		return err
	}
	return saveAndReload(setup, values, "", out)
}

func Set(setup Setup, sets map[string]string, out io.Writer) error {
	values, err := setup.Values()
	if err != nil {
		return err
	}
	maps.Copy(values, sets)
	return saveAndReload(setup, values, "set "+strings.Join(slices.Sorted(maps.Keys(sets)), " ")+"; ", out)
}

func saveAndReload(setup Setup, values map[string]string, change string, out io.Writer) error {
	written, err := Save(setup, values)
	if err != nil {
		return err
	}
	if setup.BrewLoaded {
		if err := run(setup.StopBrew(), "stopping brew services llama.cpp"); err != nil {
			return err
		}
		fmt.Fprintf(out, "stopped brew services llama.cpp; the %s agent runs the server now\n", launchd.Label)
	}
	if err := run(setup.Reload(), "reloading "+launchd.Label); err != nil {
		return err
	}
	fmt.Fprintf(out, "%s%s; reloaded %s\n", change, describe(setup.Path, written), launchd.Label)
	return nil
}

func run(command *exec.Cmd, action string) error {
	output, err := command.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %w: %s", action, err, strings.TrimSpace(string(output)))
	}
	return nil
}

func describe(path string, written bool) string {
	if written {
		return "wrote " + path
	}
	return path + " unchanged"
}
