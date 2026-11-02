---
triggers:
  - suffix: .go
  - command: go test
---

Go: `gofmt` and `go vet` must pass. Tests are table tests
(`for _, tc := range cases`) in `X_test.go` beside `X.go`. Run one package
quietly, `cd go && go test ./internal/NAME/...`, before the whole module,
`cd go && go test ./...`.
