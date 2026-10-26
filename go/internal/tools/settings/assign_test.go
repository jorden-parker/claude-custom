package settings

import (
	"reflect"
	"testing"
)

var assignableTools = []string{"Bash", "WebFetch", "Read"}

func TestParseAssignmentReadsEveryForm(t *testing.T) {
	cases := []struct {
		text     string
		wantName string
		want     ToolState
	}{
		{"WebFetch=allow", "WebFetch", ToolState{Permission: Allow}},
		{"WebFetch=ask", "WebFetch", ToolState{Permission: Ask}},
		{"WebFetch=deny", "WebFetch", ToolState{Permission: Deny}},
		{"WebFetch=default", "WebFetch", ToolState{}},
		{"WebFetch=allow,off", "WebFetch", ToolState{Permission: Allow, Disabled: true}},
		{"Read=ask,off", "Read", ToolState{Permission: Ask, Disabled: true}},
	}
	for _, c := range cases {
		name, got, err := ParseAssignment(c.text, assignableTools)
		if err != nil {
			t.Errorf("%s: unexpected error %v", c.text, err)
			continue
		}
		if name != c.wantName || got != c.want {
			t.Errorf("%s: got %s %+v", c.text, name, got)
		}
	}
}

func TestParseAssignmentRejectsInvalidInput(t *testing.T) {
	cases := []struct {
		name string
		text string
	}{
		{"unknown tool", "Nope=allow"},
		{"unknown permission", "Bash=maybe"},
		{"deny with off", "Bash=deny,off"},
		{"default with off", "Bash=default,off"},
		{"missing permission", "Bash"},
	}
	for _, c := range cases {
		if _, _, err := ParseAssignment(c.text, assignableTools); err == nil {
			t.Errorf("%s: expected an error for %q", c.name, c.text)
		}
	}
}

func TestParseAssignmentStateFeedsWrite(t *testing.T) {
	name, state, err := ParseAssignment("WebFetch=deny", assignableTools)
	if err != nil {
		t.Fatal(err)
	}
	written, err := Write([]byte(`{}`), map[string]ToolState{name: state})
	if err != nil {
		t.Fatal(err)
	}
	lists := permissionsOf(t, written)
	if !reflect.DeepEqual(lists["deny"], []string{"WebFetch"}) {
		t.Fatalf("got %v", lists)
	}
}
