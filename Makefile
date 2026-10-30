SHELL := /bin/sh
HOOK_TESTS := $(wildcard shared/hooks/*.test.sh)
SHELL_SCRIPTS := .claude/verify ollama/drafts/opener.test.sh shared/mcp/repo-tools.test.sh shared/mcp/dev-server.test.sh shared/hooks/dev-server-guard.test.sh .claude/verify.test.sh bin/claude-custom bin/claude-ollama bin/ollama-models bin/ollama-models.test.sh bin/claude-tools bin/ollama-agent bin/check-config bin/claude-ollama.test.sh bin/speed-check.test.sh bin/pr-review-local.test.sh bin/pr-review-eval.test.sh personal/claude.sh personal/settings-path personal/install.test.sh bin/ollama-cache-probe.test.sh bin/ollama-profiles bin/ollama-profiles.test.sh bin/tool-telemetry-report.test.sh $(HOOK_TESTS) shared/mcp/code-search.test.sh .husky/staged-checks.sh shared/hooks/fallow-after-edit.sh shared/hooks/fallow-command-guard.sh shared/hooks/fallow-mark-preview.sh shared/hooks/fallow-lib.sh shared/hooks/fallow-test-lib.sh bin/messages-bench.test.sh bin/backend-bench-off bin/backend-bench-off.test.sh bin/backend-bench-report.test.sh bin/extract-mtp-weights.test.sh bin/gguf-inspect.test.sh bin/console-smoke bin/console-smoke.test.sh bin/model-upgrade.test.sh
JSON_FILES := $(wildcard ollama/settings.*.json) ollama/sizes.json ollama/model-digests.json ollama/profile-template.json ollama/qwen-settings.template.json ollama/hooks.extra.json $(wildcard shared/settings/*.json) personal/settings.tokens.json personal/settings.tokens.template.json project/settings.local.json

.PHONY: test test-verify test-hooks test-install test-launcher test-models check-config check-profiles test-profiles test-gguf test-report test-console test-smoke smoke-console test-probe test-bench test-speed test-review test-search test-drafts test-go test-web test-all check-json shellcheck

NPROC := $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

test:
	$(MAKE) -j$(NPROC) --no-print-directory test-all

test-all: shellcheck check-json test-verify test-hooks test-install test-launcher test-models check-config check-profiles test-profiles test-gguf test-report test-console test-smoke test-probe test-bench test-speed test-review test-search test-drafts test-go test-web

test-verify:
	.claude/verify.test.sh

test-hooks:
	@for script in $(HOOK_TESTS); do $$script || exit 1; done

test-install:
	personal/install.test.sh

test-launcher:
	bin/claude-ollama.test.sh

test-models:
	bin/ollama-models.test.sh
	bin/model-upgrade.test.sh

check-config:
	bin/check-config

check-profiles:
	bin/ollama-profiles --check

test-profiles:
	bin/ollama-profiles.test.sh

test-gguf:
	bin/gguf-inspect.test.sh

test-report:
	bin/tool-telemetry-report.test.sh

test-console:
	bin/console-run.test.sh

test-smoke:
	bin/console-smoke.test.sh

smoke-console:
	bin/console-smoke

test-probe:
	bin/ollama-cache-probe.test.sh

test-bench:
	bin/messages-bench.test.sh
	bin/extract-mtp-weights.test.sh
	bin/backend-bench-report.test.sh
	bin/backend-bench-off.test.sh

test-speed:
	bin/speed-check.test.sh

test-review:
	bin/pr-review-local.test.sh
	bin/pr-review-eval.test.sh

test-search:
	shared/mcp/code-search.test.sh
	shared/mcp/repo-tools.test.sh
	shared/mcp/dev-server.test.sh

test-drafts:
	ollama/drafts/opener.test.sh

test-go:
	cd go && go test ./...

test-web:
	[ -f web/console/node_modules/.modules.yaml ] && [ ! web/console/pnpm-lock.yaml -nt web/console/node_modules/.modules.yaml ] || pnpm --dir web/console install --frozen-lockfile
	pnpm --dir web/console test && pnpm --dir web/console exec tsc --noEmit

check-json:
	@for file in $(JSON_FILES); do jq . $$file >/dev/null || exit 1; done

shellcheck:
	shellcheck -S warning $(SHELL_SCRIPTS)
