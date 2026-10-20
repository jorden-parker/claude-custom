package launchd

import (
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"maps"
	"slices"
	"strings"
)

const (
	plistHeader = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
`
	plistFooter    = "</dict>\n</plist>\n"
	environmentKey = "EnvironmentVariables"
)

type Agent struct {
	Label   string
	Program string
	LogPath string
	Env     map[string]string
}

func Render(agent Agent) []byte {
	var b strings.Builder
	b.WriteString(plistHeader)
	writeEntry(&b, "Label", stringValue(agent.Label))
	writeEntry(&b, "ProgramArguments", "<array>"+stringValue(agent.Program)+stringValue("serve")+"</array>")
	b.WriteString("  <key>" + environmentKey + "</key>\n  <dict>\n")
	for _, name := range slices.Sorted(maps.Keys(agent.Env)) {
		b.WriteString("  ")
		writeEntry(&b, name, stringValue(agent.Env[name]))
	}
	b.WriteString("  </dict>\n")
	writeEntry(&b, "RunAtLoad", "<true/>")
	writeEntry(&b, "KeepAlive", "<true/>")
	if agent.LogPath != "" {
		writeEntry(&b, "StandardOutPath", stringValue(agent.LogPath))
		writeEntry(&b, "StandardErrorPath", stringValue(agent.LogPath))
	}
	b.WriteString(plistFooter)
	return []byte(b.String())
}

func writeEntry(b *strings.Builder, name, value string) {
	b.WriteString("  <key>" + escape(name) + "</key>" + value + "\n")
}

func stringValue(text string) string {
	return "<string>" + escape(text) + "</string>"
}

func escape(text string) string {
	var b bytes.Buffer
	xml.EscapeText(&b, []byte(text))
	return b.String()
}

func ReadEnv(data []byte) (map[string]string, error) {
	decoder := xml.NewDecoder(bytes.NewReader(data))
	for {
		start, err := nextStart(decoder)
		if errors.Is(err, io.EOF) {
			return map[string]string{}, nil
		}
		if err != nil {
			return nil, err
		}
		if start.Name.Local != "key" {
			continue
		}
		name, err := elementText(decoder, start)
		if err != nil {
			return nil, err
		}
		if name == environmentKey {
			return readStringDict(decoder)
		}
	}
}

func readStringDict(decoder *xml.Decoder) (map[string]string, error) {
	if _, err := expectStart(decoder, "dict"); err != nil {
		return nil, err
	}
	env := map[string]string{}
	for {
		token, err := nextElementToken(decoder)
		if err != nil {
			return nil, err
		}
		if _, closing := token.(xml.EndElement); closing {
			return env, nil
		}
		name, err := elementText(decoder, token.(xml.StartElement))
		if err != nil {
			return nil, err
		}
		valueStart, err := expectStart(decoder, "string")
		if err != nil {
			return nil, fmt.Errorf("%s %s: %w", environmentKey, name, err)
		}
		if env[name], err = elementText(decoder, valueStart); err != nil {
			return nil, err
		}
	}
}

func expectStart(decoder *xml.Decoder, element string) (xml.StartElement, error) {
	token, err := nextElementToken(decoder)
	if err != nil {
		return xml.StartElement{}, err
	}
	start, ok := token.(xml.StartElement)
	if !ok || start.Name.Local != element {
		return xml.StartElement{}, fmt.Errorf("expected <%s>", element)
	}
	return start, nil
}

func nextStart(decoder *xml.Decoder) (xml.StartElement, error) {
	for {
		token, err := decoder.Token()
		if err != nil {
			return xml.StartElement{}, err
		}
		if start, ok := token.(xml.StartElement); ok {
			return start, nil
		}
	}
}

func nextElementToken(decoder *xml.Decoder) (xml.Token, error) {
	for {
		token, err := decoder.Token()
		if errors.Is(err, io.EOF) {
			return nil, io.ErrUnexpectedEOF
		}
		if err != nil {
			return nil, err
		}
		switch token.(type) {
		case xml.StartElement, xml.EndElement:
			return token, nil
		}
	}
}

func elementText(decoder *xml.Decoder, start xml.StartElement) (string, error) {
	var text string
	err := decoder.DecodeElement(&text, &start)
	return text, err
}
