package main

import (
	"fmt"
	"os"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/picker/profiles"
	"github.com/jordenparker/claude-custom/go/internal/picker/ui"
)

const (
	exitCancelled = 1
	exitUsage     = 2
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: model-picker <ollama-profile-dir>")
		os.Exit(exitUsage)
	}
	size, err := pick(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, "model-picker:", err)
		os.Exit(exitUsage)
	}
	if size == "" {
		os.Exit(exitCancelled)
	}
	fmt.Println(size)
}

func pick(profileDir string) (string, error) {
	configured, err := profiles.Load(profileDir)
	if err != nil {
		return "", err
	}
	if len(configured) == 0 {
		return "", fmt.Errorf("no profiles in %s (need settings.<size>.json and Modelfile.<size>)", profileDir)
	}
	final, err := tea.NewProgram(ui.New(configured, profiles.EmbeddingModel()), tea.WithOutput(os.Stderr)).Run()
	if err != nil {
		return "", err
	}
	chosen, ok := final.(ui.Model).Chosen()
	if !ok {
		return "", nil
	}
	return chosen.Size, nil
}
