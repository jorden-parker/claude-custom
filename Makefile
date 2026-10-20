SHELL := /bin/sh
HOOK_TESTS := $(wildcard shared/hooks/*.test.sh)
SHELL_SCRIPTS := .claude/verify .claude/verify.test.sh bin/claude-custom bin/claude-ollama bin/claude-tools bin/ollama-agent bin/check-config bin/claude-ollama.test.sh personal/claude.sh personal/settings-path personal/install.test.sh bin/ollama-cache-probe.test.sh bin/ollama-profiles bin/ollama-profiles.test.sh bin/tool-telemetry-report.test.sh $(HOOK_TESTS) shared/mcp/code-search.test.sh .husky/staged-checks.sh shared/hooks/fallow-after-edit.sh shared/hooks/fallow-command-guard.sh shared/hooks/fallow-mark-preview.sh shared/hooks/fallow-lib.sh shared/hooks/fallow-test-lib.sh bin/messages-bench.test.sh bin/backend-bench-off bin/backend-bench-off.test.sh bin/backend-bench-report.test.sh bin/extract-mtp-weights.test.sh
JSON_FILES := $(wildcard ollama/settings.*.json) ollama/sizes.json ollama/profile-template.json ollama/hooks.extra.json $(wildcard shared/settings/*.json) personal/settings.tokens.json personal/settings.tokens.template.json project/settings.local.json

.PHONY: test test-verify test-hooks test-install test-launcher check-config check-profiles test-profiles test-report test-probe test-bench test-search test-go check-json shellcheck

test: shellcheck check-json test-verify test-hooks test-install test-launcher check-config check-profiles test-profiles test-report test-probe test-bench test-search test-go

test-verify:
	.claude/verify.test.sh

test-hooks:
	@for script in $(HOOK_TESTS); do $$script || exit 1; done

test-install:
	personal/install.test.sh

test-launcher:
	bin/claude-ollama.test.sh

check-config:
	bin/check-config

check-profiles:
	bin/ollama-profiles --check

test-profiles:
	bin/ollama-profiles.test.sh

test-report:
	bin/tool-telemetry-report.test.sh

test-probe:
	bin/ollama-cache-probe.test.sh

test-bench:
	bin/messages-bench.test.sh
	bin/extract-mtp-weights.test.sh
	bin/backend-bench-report.test.sh
	bin/backend-bench-off.test.sh

test-search:
	shared/mcp/code-search.test.sh

test-go:
	cd go && go test ./...

check-json:
	@for file in $(JSON_FILES); do jq . $$file >/dev/null || exit 1; done

shellcheck:
	shellcheck -S warning $(SHELL_SCRIPTS)
