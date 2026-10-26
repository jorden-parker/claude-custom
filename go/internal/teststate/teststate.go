package teststate

import (
	"fmt"
	"os"
)

func Run(run func() int) int {
	state, err := os.MkdirTemp("", "console-state-")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer os.RemoveAll(state)
	if err := os.Setenv("CLAUDE_CONSOLE_STATE_DIR", state); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return run()
}
