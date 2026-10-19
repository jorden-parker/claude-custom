SHELL := /bin/sh
HOOK_TESTS := $(wildcard shared/hooks/*.test.sh)
SHELL_SCRIPTS := bin/claude-custom bin/claude-ollama bin/claude-tools bin/check-config bin/claude-ollama.test.sh personal/claude.sh personal/settings-path personal/install.test.sh bin/ollama-cache-probe.test.sh $(HOOK_TESTS) shared/mcp/code-search.test.sh .husky/staged-checks.sh shared/hooks/fallow-after-edit.sh shared/hooks/fallow-command-guard.sh shared/hooks/fallow-mark-preview.sh shared/hooks/fallow-lib.sh shared/hooks/fallow-test-lib.sh
JSON_FILES := $(wildcard ollama/settings.*.json) personal/settings.tokens.json project/settings.local.json

.PHONY: test test-hooks test-install test-launcher check-config test-probe test-search test-go check-json shellcheck

test: shellcheck check-json test-hooks test-install test-launcher check-config test-probe test-search test-go

test-hooks:
	@for script in $(HOOK_TESTS); do $$script || exit 1; done

test-install:
	personal/install.test.sh

test-launcher:
	bin/claude-ollama.test.sh

check-config:
	bin/check-config

test-probe:
	bin/ollama-cache-probe.test.sh

test-search:
	shared/mcp/code-search.test.sh

test-go:
	cd go && go test ./...

check-json:
	@for file in $(JSON_FILES); do jq . $$file >/dev/null || exit 1; done

shellcheck:
	shellcheck -S warning $(SHELL_SCRIPTS)
