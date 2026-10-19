package profiles

import "os"

const DefaultEmbeddingModel = "qwen3-embedding:0.6b"

func EmbeddingModel() string {
	if name := os.Getenv("CODE_SEARCH_MODEL"); name != "" {
		return name
	}
	return DefaultEmbeddingModel
}
