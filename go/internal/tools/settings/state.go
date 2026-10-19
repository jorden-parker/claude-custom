package settings

type Permission int

const (
	Default Permission = iota
	Allow
	Ask
	Deny
)

var permissionNames = [...]string{"default", "allow", "ask", "deny"}

func (p Permission) String() string {
	return permissionNames[p]
}

type ToolState struct {
	Permission Permission
	Disabled   bool
}

func (s ToolState) InContext() bool {
	return !s.Disabled && s.Permission != Deny
}

func (s ToolState) WithPermission(p Permission) ToolState {
	if p == Default || p == Deny || s.Permission == Deny {
		return ToolState{Permission: p}
	}
	return ToolState{Permission: p, Disabled: s.Disabled}
}

func (s ToolState) NextPermission() ToolState {
	return s.WithPermission((s.Permission + 1) % Permission(len(permissionNames)))
}

func (s ToolState) ToggledContext() ToolState {
	switch {
	case s.Permission == Deny:
		return ToolState{}
	case s.Permission == Default:
		return ToolState{Permission: Deny}
	default:
		return ToolState{Permission: s.Permission, Disabled: !s.Disabled}
	}
}
