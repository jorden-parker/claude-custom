package launchd

import (
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"strings"
)

const (
	plistHeader = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
`
	plistFooter  = "</dict>\n</plist>\n"
	argumentsKey = "ProgramArguments"
	Host         = "127.0.0.1"
	Port         = "11435"
)

type Agent struct {
	Label     string
	Arguments []string
	LogPath   string
}

type Server struct {
	Program   string
	Presets   string
	ModelsMax string
	LogFile   string
	LogPath   string
}

func (s Server) Agent() Agent {
	return Agent{
		Label:   Label,
		LogPath: s.LogPath,
		Arguments: []string{
			s.Program,
			"--models-preset", s.Presets,
			"--models-max", s.ModelsMax,
			"--host", Host,
			"--port", Port,
			"--log-file", s.LogFile,
			"--metrics",
		},
	}
}

func Render(agent Agent) []byte {
	var b strings.Builder
	b.WriteString(plistHeader)
	writeEntry(&b, "Label", stringValue(agent.Label))
	b.WriteString("  <key>" + argumentsKey + "</key>\n  <array>\n")
	for _, argument := range agent.Arguments {
		b.WriteString("    " + stringValue(argument) + "\n")
	}
	b.WriteString("  </array>\n")
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

func ReadArguments(data []byte) ([]string, error) {
	decoder := xml.NewDecoder(bytes.NewReader(data))
	for {
		start, err := nextStart(decoder)
		if errors.Is(err, io.EOF) {
			return []string{}, nil
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
		if name == argumentsKey {
			return readStringArray(decoder)
		}
	}
}

func readStringArray(decoder *xml.Decoder) ([]string, error) {
	if _, err := expectStart(decoder, "array"); err != nil {
		return nil, err
	}
	arguments := []string{}
	for {
		token, err := nextElementToken(decoder)
		if err != nil {
			return nil, err
		}
		if _, closing := token.(xml.EndElement); closing {
			return arguments, nil
		}
		start := token.(xml.StartElement)
		if start.Name.Local != "string" {
			return nil, fmt.Errorf("%s: expected <string>", argumentsKey)
		}
		text, err := elementText(decoder, start)
		if err != nil {
			return nil, err
		}
		arguments = append(arguments, text)
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
