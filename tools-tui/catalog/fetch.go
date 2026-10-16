package catalog

import (
	"fmt"
	"io"
	"net/http"
	"time"
)

const DocsURL = "https://code.claude.com/docs/en/tools-reference.md"

var httpClient = &http.Client{Timeout: 20 * time.Second}

func Fetch(url string) ([]Tool, error) {
	response, err := httpClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetching %s: %s", url, response.Status)
	}
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, err
	}
	return Parse(body)
}
