package main

import "testing"

func TestConflictingTarget(t *testing.T) {
	tests := []struct {
		name        string
		settingsSet bool
		scopeArg    string
		want        bool
	}{
		{name: "neither given", settingsSet: false, scopeArg: "", want: false},
		{name: "scope only", settingsSet: false, scopeArg: "user", want: false},
		{name: "settings only", settingsSet: true, scopeArg: "", want: false},
		{name: "settings and scope", settingsSet: true, scopeArg: "user", want: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := conflictingTarget(tt.settingsSet, tt.scopeArg); got != tt.want {
				t.Errorf("conflictingTarget(%v, %q) = %v, want %v", tt.settingsSet, tt.scopeArg, got, tt.want)
			}
		})
	}
}
