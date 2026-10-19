package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/tools/catalog"
	"github.com/jordenparker/claude-custom/go/internal/tools/settings"
	"github.com/jordenparker/claude-custom/go/internal/tools/ui"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "claude-tools:", err)
		os.Exit(1)
	}
}

func run() error {
	defaultSettings, err := settings.DefaultPath()
	if err != nil {
		return err
	}
	snapshotPath, err := catalog.DefaultSnapshotPath()
	if err != nil {
		return err
	}
	settingsFlag := flag.String("settings", defaultSettings, "Claude Code settings file to edit")
	flag.Usage = printUsage
	flag.Parse()
	if flag.NArg() > 1 {
		printUsage()
		os.Exit(2)
	}
	files, activePath, err := settingsFiles(*settingsFlag, flag.Arg(0))
	if err != nil {
		return err
	}

	model, err := ui.New(ui.Config{SettingsPath: activePath, SettingsFiles: files, SnapshotPath: snapshotPath, DocsURL: catalog.DocsURL})
	if err != nil {
		return fmt.Errorf("reading %s: %w", activePath, err)
	}
	_, err = tea.NewProgram(model).Run()
	return err
}

func printUsage() {
	fmt.Fprintln(flag.CommandLine.Output(), "usage: claude-tools [user|project|local|FILE]")
	flag.PrintDefaults()
}

func settingsFiles(settingsFlag, scopeArg string) ([]settings.File, string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, "", err
	}
	cwd, err := os.Getwd()
	if err != nil {
		return nil, "", err
	}
	chosen := settingsFlag
	if scopeArg != "" {
		chosen = settings.ResolvePath(home, cwd, scopeArg)
	}
	activePath, err := filepath.Abs(chosen)
	return settings.Files(home, cwd, chosen), activePath, err
}
