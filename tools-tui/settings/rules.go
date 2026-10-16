package settings

import (
	"bytes"
	"encoding/json"
	"errors"
	"slices"

	"github.com/tidwall/gjson"
	"github.com/tidwall/sjson"
)

var ruleLists = []string{"allow", "ask", "deny"}

func Read(data []byte, toolNames []string) (map[string]ToolState, error) {
	if !gjson.ValidBytes(data) {
		return nil, errors.New("settings file is not valid JSON")
	}
	lists := map[string][]string{}
	for _, list := range ruleLists {
		lists[list] = rulesIn(data, list)
	}
	states := make(map[string]ToolState, len(toolNames))
	for _, name := range toolNames {
		states[name] = stateFromRules(name, lists)
	}
	return states, nil
}

func stateFromRules(name string, lists map[string][]string) ToolState {
	denied := slices.Contains(lists["deny"], name)
	permission := Default
	switch {
	case slices.Contains(lists["allow"], name):
		permission = Allow
	case slices.Contains(lists["ask"], name):
		permission = Ask
	case denied:
		return ToolState{Permission: Deny}
	}
	return ToolState{Permission: permission, Disabled: denied}
}

func Write(data []byte, states map[string]ToolState) ([]byte, error) {
	if !gjson.ValidBytes(data) {
		return nil, errors.New("settings file is not valid JSON")
	}
	result := data
	for _, list := range ruleLists {
		updated, err := writeList(result, list, states)
		if err != nil {
			return nil, err
		}
		result = updated
	}
	return indent(result)
}

func writeList(data []byte, list string, states map[string]ToolState) ([]byte, error) {
	path := "permissions." + list
	existing := gjson.GetBytes(data, path)
	rules := mergeRules(rulesIn(data, list), managedRulesFor(list, states), states)
	if len(rules) == 0 && !existing.Exists() {
		return data, nil
	}
	return sjson.SetBytes(data, path, rules)
}

func rulesIn(data []byte, list string) []string {
	var rules []string
	for _, rule := range gjson.GetBytes(data, "permissions."+list).Array() {
		rules = append(rules, rule.String())
	}
	return rules
}

func mergeRules(existing, managed []string, states map[string]ToolState) []string {
	rules := []string{}
	for _, rule := range existing {
		if _, isManaged := states[rule]; !isManaged {
			rules = append(rules, rule)
		}
	}
	return append(rules, managed...)
}

func managedRulesFor(list string, states map[string]ToolState) []string {
	var names []string
	for name, state := range states {
		if belongsIn(list, state) {
			names = append(names, name)
		}
	}
	slices.Sort(names)
	return names
}

func belongsIn(list string, state ToolState) bool {
	switch list {
	case "allow":
		return state.Permission == Allow
	case "ask":
		return state.Permission == Ask
	default:
		return !state.InContext()
	}
}

func indent(data []byte) ([]byte, error) {
	var compact, pretty bytes.Buffer
	if err := json.Compact(&compact, data); err != nil {
		return nil, err
	}
	if err := json.Indent(&pretty, compact.Bytes(), "", "  "); err != nil {
		return nil, err
	}
	pretty.WriteByte('\n')
	return pretty.Bytes(), nil
}
