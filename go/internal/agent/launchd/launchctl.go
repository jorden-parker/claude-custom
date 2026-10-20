package launchd

import (
	"os/exec"
	"strconv"
)

const (
	BrewLabel    = "homebrew.mxcl.ollama"
	reloadScript = `launchctl bootout "$1" 2>/dev/null
while launchctl print "$1" >/dev/null 2>&1; do sleep 0.2; done
launchctl bootstrap "$2" "$3"`
)

func ReloadCommand(path string, uid int) *exec.Cmd {
	return exec.Command("sh", "-c", reloadScript, "sh", ServiceTarget(uid, Label), domain(uid), path)
}

func ServiceLoaded(uid int, label string) bool {
	return exec.Command("launchctl", "print", ServiceTarget(uid, label)).Run() == nil
}

func ServiceTarget(uid int, label string) string {
	return domain(uid) + "/" + label
}

func domain(uid int) string {
	return "gui/" + strconv.Itoa(uid)
}
