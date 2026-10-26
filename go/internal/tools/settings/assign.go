package settings

import (
	"fmt"
	"slices"
	"strings"
)

const disabledSuffix = ",off"

func ParseAssignment(text string, known []string) (string, ToolState, error) {
	name, rest, _ := strings.Cut(text, "=")
	if !slices.Contains(known, name) {
		return "", ToolState{}, fmt.Errorf("unknown tool %q", name)
	}
	permissionText, disabled := strings.CutSuffix(rest, disabledSuffix)
	permission, err := parsePermission(permissionText)
	if err != nil {
		return "", ToolState{}, err
	}
	if disabled && (permission == Default || permission == Deny) {
		return "", ToolState{}, fmt.Errorf("%q: %s only applies to allow or ask", text, disabledSuffix)
	}
	return name, ToolState{Disabled: disabled}.WithPermission(permission), nil
}

func parsePermission(text string) (Permission, error) {
	for permission := Default; permission <= Deny; permission++ {
		if permission.String() == text {
			return permission, nil
		}
	}
	return Default, fmt.Errorf("unknown permission %q", text)
}
