SHELL := /bin/sh
GUARD := $(CURDIR)/shared/testing/test-guard
HOOK_TESTS := $(wildcard shared/hooks/*.test.sh)
SHELL_SCRIPTS := shared/testing/test-guard shared/testing/test-guard.test.sh shared/testing/stub-llama-lib.sh shared/testing/stub-llama-server.test.sh shared/model_server.test.sh shared/sandbox-env shared/sandbox-env.test.sh shared/host-env shared/host-env.test.sh shared/profile-overlay shared/profile-overlay.test.sh shared/relaunch_dir.test.sh personal/launch personal/settings-path.test.sh .claude/verify ollama/drafts/opener.test.sh ollama/incidents/watcher.test.sh ollama/incidents/incident_log.test.sh shared/mcp/repo-tools.test.sh shared/mcp/dev-server.test.sh shared/hooks/dev-server-guard.test.sh .claude/verify.test.sh bin/claude-custom bin/claude-ollama bin/claude-ollama-doctor bin/claude-ollama-doctor.test.sh bin/claude-ollama-qwen bin/claude-ollama-qwen.test.sh $(wildcard bin/lib/*.sh) bin/ollama-models bin/ollama-models.test.sh bin/claude-tools bin/ollama-agent bin/check-config bin/claude-ollama.test.sh bin/speed-check.test.sh bin/pr-review-local.test.sh bin/pr-review-eval.test.sh personal/claude.sh personal/settings-path personal/install.test.sh bin/ollama-cache-probe.test.sh bin/ollama-profiles bin/ollama-profiles.test.sh bin/tool-telemetry-report.test.sh $(HOOK_TESTS) shared/mcp/code-search.test.sh .husky/staged-checks.sh shared/hooks/fallow-after-edit.sh shared/hooks/fallow-command-guard.sh shared/hooks/fallow-mark-preview.sh shared/hooks/fallow-lib.sh shared/hooks/fallow-test-lib.sh bin/messages-bench.test.sh bin/messages-proxy.test.sh bin/backend-bench-off bin/backend-bench-off.test.sh bin/backend-bench-report.test.sh bin/extract-mtp-weights.test.sh bin/gguf-inspect.test.sh bin/console-smoke bin/console-smoke.test.sh bin/model-upgrade.test.sh bin/task-eval.test.sh bin/sync-fingerprint bin/sync-fingerprint.test.sh bin/ollama-lease bin/mock-spike bin/ollama-lease.test.sh bin/prefix-ab.test.sh bin/skill-check.test.sh bin/skill-listing.test.sh bin/tool-budget.test.sh bin/mock-spike.test.sh ollama/incidents/ladder.test.sh ollama/incidents/why.test.sh ollama/rescue.test.sh
JSON_FILES := $(wildcard ollama/settings.*.json) ollama/sizes.json ollama/model-digests.json ollama/profile-template.json ollama/qwen-settings.template.json ollama/hooks.extra.json $(wildcard shared/settings/*.json) personal/settings.tokens.json personal/settings.tokens.template.json project/settings.local.json

.PHONY: test test-sandbox-env test-overlay test-verify test-hooks test-install test-launcher test-doctor test-qwen test-relaunch test-lease test-incidents test-budget test-skill-check test-mock-spike check-tests-wired test-sync test-models check-config check-profiles test-profiles test-gguf test-report test-console test-smoke smoke-console test-probe test-bench test-speed test-review test-tasks test-search test-drafts test-go test-web test-all check-json shellcheck

NPROC := $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

test:
	$(MAKE) -k -j$(NPROC) --no-print-directory test-all

test-all: shellcheck check-json check-tests-wired test-sandbox-env test-overlay test-verify test-hooks test-install test-launcher test-doctor test-qwen test-relaunch test-lease test-incidents test-budget test-skill-check test-mock-spike test-sync test-models check-config check-profiles test-profiles test-gguf test-report test-console test-smoke test-probe test-bench test-speed test-review test-tasks test-search test-drafts test-go test-web

test-sandbox-env:
	shared/sandbox-env.test.sh
	shared/host-env.test.sh

test-overlay:
	shared/profile-overlay.test.sh
	personal/settings-path.test.sh

test-verify:
	.claude/verify.test.sh

test-hooks:
	@for script in $(HOOK_TESTS); do $$script || exit 1; done

test-install:
	$(GUARD) personal/install.test.sh

test-launcher:
	shared/testing/test-guard.test.sh
	$(GUARD) bin/claude-ollama.test.sh
	$(GUARD) bin/lib/model-server.test.sh
	$(GUARD) shared/testing/stub-llama-server.test.sh
	$(GUARD) shared/model_server.test.sh

test-doctor:
	$(GUARD) bin/claude-ollama-doctor.test.sh

test-qwen:
	$(GUARD) bin/claude-ollama-qwen.test.sh

test-relaunch:
	$(GUARD) shared/relaunch_dir.test.sh

test-models:
	$(GUARD) bin/ollama-models.test.sh
	$(GUARD) bin/model-upgrade.test.sh

check-config:
	$(GUARD) bin/check-config

check-profiles:
	$(GUARD) bin/ollama-profiles --check

test-profiles:
	$(GUARD) bin/ollama-profiles.test.sh

test-gguf:
	$(GUARD) bin/gguf-inspect.test.sh

test-report:
	bin/tool-telemetry-report.test.sh

test-console:
	bin/console-run.test.sh

test-smoke:
	$(GUARD) bin/console-smoke.test.sh

smoke-console:
	bin/console-smoke

test-probe:
	$(GUARD) bin/ollama-cache-probe.test.sh

test-bench:
	$(GUARD) bin/messages-bench.test.sh
	$(GUARD) bin/messages-proxy.test.sh
	$(GUARD) bin/extract-mtp-weights.test.sh
	$(GUARD) bin/backend-bench-report.test.sh
	$(GUARD) bin/backend-bench-off.test.sh

test-speed:
	$(GUARD) bin/speed-check.test.sh

test-review:
	$(GUARD) bin/pr-review-local.test.sh
	$(GUARD) bin/pr-review-eval.test.sh

test-tasks:
	$(GUARD) bin/task-eval.test.sh

test-search:
	$(GUARD) shared/mcp/code-search.test.sh
	$(GUARD) shared/mcp/repo-tools.test.sh
	$(GUARD) shared/mcp/dev-server.test.sh

test-drafts:
	$(GUARD) ollama/drafts/opener.test.sh
	$(GUARD) ollama/incidents/watcher.test.sh
	$(GUARD) ollama/incidents/incident_log.test.sh

test-go:
	cd go && $(GUARD) go test ./...

test-web:
	[ -f web/console/node_modules/.modules.yaml ] && [ ! web/console/pnpm-lock.yaml -nt web/console/node_modules/.modules.yaml ] || pnpm --dir web/console install --frozen-lockfile
	$(GUARD) pnpm --dir web/console test && pnpm --dir web/console exec tsc --noEmit

check-json:
	@for file in $(JSON_FILES); do jq . $$file >/dev/null || exit 1; done

shellcheck:
	shellcheck -S warning $(SHELL_SCRIPTS)

test-sync:
	$(GUARD) bin/sync-fingerprint.test.sh

test-lease:
	$(GUARD) bin/ollama-lease.test.sh

test-incidents:
	$(GUARD) ollama/incidents/ladder.test.sh
	$(GUARD) ollama/incidents/why.test.sh
	$(GUARD) ollama/rescue.test.sh

test-budget:
	$(GUARD) bin/tool-budget.test.sh
	$(GUARD) bin/prefix-ab.test.sh

test-skill-check:
	$(GUARD) bin/skill-check.test.sh
	$(GUARD) bin/skill-listing.test.sh

test-mock-spike:
	$(GUARD) bin/mock-spike.test.sh

check-tests-wired:
	@missing=$$(git ls-files '*.test.sh' | grep -v -e '^eval/' -e '^shared/hooks/' | while read -r t; do grep -v '^SHELL_SCRIPTS' Makefile | grep -qF "$$t" || echo "$$t"; done); [ -z "$$missing" ] || { echo "not run by make test: $$missing"; exit 1; }
