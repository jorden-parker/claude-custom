package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"

	"github.com/jordenparker/claude-custom/go/internal/tools/catalog"
	"github.com/jordenparker/claude-custom/go/internal/tools/report"
	"github.com/jordenparker/claude-custom/go/internal/tools/settings"
	"github.com/jordenparker/claude-custom/go/internal/tools/ui"
)

var errNoCatalog = errors.New("no tool catalog yet; open claude-tools once and sync")

const catalogMaxAge = 7 * 24 * time.Hour

type assignments []string

func (a *assignments) String() string {
	return strings.Join(*a, " ")
}

func (a *assignments) Set(text string) error {
	*a = append(*a, text)
	return nil
}

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
	jsonFlag := flag.Bool("json", false, "print the tools and their permissions as JSON, then exit")
	var sets assignments
	flag.Var(&sets, "set", "set NAME=default|allow|ask|deny[,off] and save the file (repeatable)")
	flag.Usage = printUsage
	flag.Parse()
	settingsSet := false
	flag.Visit(func(setFlag *flag.Flag) {
		if setFlag.Name == "settings" {
			settingsSet = true
		}
	})
	if flag.NArg() > 1 || (*jsonFlag && len(sets) > 0) || conflictingTarget(settingsSet, flag.Arg(0)) {
		printUsage()
		os.Exit(2)
	}
	files, activePath, err := settingsFiles(*settingsFlag, flag.Arg(0))
	if err != nil {
		return err
	}
	if *jsonFlag {
		return printReport(activePath, snapshotPath)
	}
	if len(sets) > 0 {
		return applyAssignments(activePath, snapshotPath, sets)
	}

	model, err := ui.New(ui.Config{SettingsPath: activePath, SettingsFiles: files, SnapshotPath: snapshotPath, DocsURL: catalog.DocsURL})
	if err != nil {
		return fmt.Errorf("reading %s: %w", activePath, err)
	}
	_, err = tea.NewProgram(model).Run()
	return err
}

func printUsage() {
	fmt.Fprintln(flag.CommandLine.Output(), "usage: claude-tools [-json | -set NAME=PERM[,off]...] [user|project|local|FILE]")
	flag.PrintDefaults()
}

func printReport(settingsPath, snapshotPath string) error {
	snapshot, err := loadCatalog(snapshotPath)
	if err != nil {
		return err
	}
	built, err := report.Build(settingsPath, snapshot.Tools)
	if err != nil {
		return err
	}
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	return encoder.Encode(built)
}

func applyAssignments(settingsPath, snapshotPath string, texts []string) error {
	snapshot, err := loadCatalog(snapshotPath)
	if err != nil {
		return err
	}
	names := toolNames(snapshot.Tools)
	data, err := settings.Load(settingsPath)
	if err != nil {
		return err
	}
	states, err := settings.Read(data, names)
	if err != nil {
		return err
	}
	for _, text := range texts {
		name, state, err := settings.ParseAssignment(text, names)
		if err != nil {
			return err
		}
		states[name] = state
	}
	written, err := settings.Write(data, states)
	if err != nil {
		return err
	}
	if err := settings.Save(settingsPath, written); err != nil {
		return err
	}
	fmt.Println("saved", settingsPath)
	return nil
}

func loadCatalog(snapshotPath string) (catalog.Snapshot, error) {
	snapshot, err := catalog.Ensure(snapshotPath, docsURL(), catalogMaxAge, time.Now())
	if err != nil {
		return snapshot, fmt.Errorf("%w: %v", errNoCatalog, err)
	}
	return snapshot, nil
}

func docsURL() string {
	if override := os.Getenv("CLAUDE_TOOLS_DOCS_URL"); override != "" {
		return override
	}
	return catalog.DocsURL
}

func toolNames(tools []catalog.Tool) []string {
	names := make([]string, 0, len(tools))
	for _, tool := range tools {
		names = append(names, tool.Name)
	}
	return names
}

func conflictingTarget(settingsSet bool, scopeArg string) bool {
	return settingsSet && scopeArg != ""
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
