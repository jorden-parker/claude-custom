package profiles

import "testing"

func TestEmbeddingModelDefaultsToQwen(t *testing.T) {
	t.Setenv("CODE_SEARCH_MODEL", "")
	if got := EmbeddingModel(); got != "qwen3-embedding:0.6b" {
		t.Fatalf("got %q", got)
	}
}

func TestEmbeddingModelFollowsCodeSearchOverride(t *testing.T) {
	t.Setenv("CODE_SEARCH_MODEL", "nomic-embed-text")
	if got := EmbeddingModel(); got != "nomic-embed-text" {
		t.Fatalf("got %q", got)
	}
}
