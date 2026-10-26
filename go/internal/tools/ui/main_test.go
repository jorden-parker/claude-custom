package ui

import (
	"os"
	"testing"

	"github.com/jordenparker/claude-custom/go/internal/teststate"
)

func TestMain(m *testing.M) {
	os.Exit(teststate.Run(m.Run))
}
