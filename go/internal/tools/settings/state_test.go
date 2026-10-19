package settings

import "testing"

func TestWithPermission(t *testing.T) {
	cases := []struct {
		name string
		from ToolState
		to   Permission
		want ToolState
	}{
		{"allow to ask keeps disabled", ToolState{Allow, true}, Ask, ToolState{Ask, true}},
		{"deny clears disabled", ToolState{Allow, true}, Deny, ToolState{Deny, false}},
		{"leaving deny re-enables", ToolState{Deny, false}, Allow, ToolState{Allow, false}},
		{"default stays enabled", ToolState{}, Default, ToolState{}},
		{"default removes every rule", ToolState{Allow, true}, Default, ToolState{}},
	}
	for _, c := range cases {
		if got := c.from.WithPermission(c.to); got != c.want {
			t.Errorf("%s: got %+v", c.name, got)
		}
	}
}

func TestNextPermissionCyclesDefaultAllowAskDeny(t *testing.T) {
	state := ToolState{}
	var order []Permission
	for range 5 {
		state = state.NextPermission()
		order = append(order, state.Permission)
	}
	want := []Permission{Allow, Ask, Deny, Default, Allow}
	for i := range want {
		if order[i] != want[i] {
			t.Fatalf("got %v", order)
		}
	}
}

func TestToggledContext(t *testing.T) {
	cases := []struct {
		name string
		from ToolState
		want ToolState
	}{
		{"allow disables and keeps allow", ToolState{Allow, false}, ToolState{Allow, true}},
		{"disabled ask re-enables", ToolState{Ask, true}, ToolState{Ask, false}},
		{"default disables as a bare deny", ToolState{}, ToolState{Deny, false}},
		{"deny re-enables as default", ToolState{Deny, false}, ToolState{}},
	}
	for _, c := range cases {
		if got := c.from.ToggledContext(); got != c.want {
			t.Errorf("%s: got %+v", c.name, got)
		}
	}
}

func TestInContext(t *testing.T) {
	if !(ToolState{Allow, false}).InContext() {
		t.Error("enabled allow should be in context")
	}
	if (ToolState{Allow, true}).InContext() {
		t.Error("disabled tool should be out of context")
	}
	if (ToolState{Deny, false}).InContext() {
		t.Error("bare deny removes the tool from context")
	}
}
