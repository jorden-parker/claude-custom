#!/usr/bin/env bash
set -u
scope="$(cd "$(dirname "$0")" && pwd)/test_scope.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
project="$sandbox/project"
mkdir -p "$project/.git" "$project/.claude" "$project/shared/hooks" "$project/go/internal/parse" "$project/web/src/lib" "$project/web/src/app/__tests__" "$project/py" "$project/other" "$sandbox/lonely"
printf '#!/bin/sh\n' > "$project/.claude/verify"
printf 'module example\n' > "$project/go/go.mod"
printf '{"name":"web"}' > "$project/web/package.json"
touch "$project/shared/hooks/tool.py" "$project/shared/hooks/tool.test.sh" \
  "$project/go/internal/parse/parse.go" "$project/go/internal/parse/render.go" "$project/go/internal/parse/parse_test.go" \
  "$project/web/src/lib/rules.ts" "$project/web/src/lib/rules.test.ts" \
  "$project/web/src/app/page.tsx" "$project/web/src/app/__tests__/page.test.tsx" \
  "$project/web/src/lib/format.ts" "$project/web/src/lib/format.spec.ts" \
  "$project/py/serve.py" "$project/py/test_serve.py" "$project/py/parse.py" "$project/py/parse_test.py" \
  "$project/other/run.sh" "$sandbox/lonely/thing.sh"

resolve() {
  python3 "$scope" "$1" "${2:-$project}"
}

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label: expected [$want], got [$got]"
    failures=$((failures + 1))
  fi
}

expect_eq 'a sibling X.test.sh' \
  "$project/shared/hooks/tool.test.sh	./shared/hooks/tool.test.sh" \
  "$(resolve "$project/shared/hooks/tool.py")"
expect_eq 'a test file resolves to itself' \
  "$project/shared/hooks/tool.test.sh	./shared/hooks/tool.test.sh" \
  "$(resolve "$project/shared/hooks/tool.test.sh")"
expect_eq 'a Go package test from the module root' \
  "$project/go/internal/parse/parse_test.go	cd go && go test ./internal/parse" \
  "$(resolve "$project/go/internal/parse/parse.go")"
expect_eq 'any _test.go in the package counts' \
  "$project/go/internal/parse/parse_test.go	cd go && go test ./internal/parse" \
  "$(resolve "$project/go/internal/parse/render.go")"
expect_eq 'no cd when the session already sits in the module' \
  "$project/go/internal/parse/parse_test.go	go test ./internal/parse" \
  "$(resolve "$project/go/internal/parse/parse.go" "$project/go")"
expect_eq 'a vitest file beside its source through the package root' \
  "$project/web/src/lib/rules.test.ts	pnpm -C web exec vitest run src/lib/rules.test.ts" \
  "$(resolve "$project/web/src/lib/rules.ts")"
expect_eq 'a vitest file under __tests__' \
  "$project/web/src/app/__tests__/page.test.tsx	pnpm -C web exec vitest run src/app/__tests__/page.test.tsx" \
  "$(resolve "$project/web/src/app/page.tsx")"
expect_eq 'a spec file' \
  "$project/web/src/lib/format.spec.ts	pnpm -C web exec vitest run src/lib/format.spec.ts" \
  "$(resolve "$project/web/src/lib/format.ts")"
expect_eq 'test_X.py runs with pytest' \
  "$project/py/test_serve.py	pytest py/test_serve.py" \
  "$(resolve "$project/py/serve.py")"
expect_eq 'X_test.py runs with pytest' \
  "$project/py/parse_test.py	pytest py/parse_test.py" \
  "$(resolve "$project/py/parse.py")"
expect_eq 'the project verify script when nothing closer matches' \
  "$project/.claude/verify	.claude/verify other/run.sh" \
  "$(resolve "$project/other/run.sh")"
expect_eq 'nothing outside a project with no verify script' \
  "" \
  "$(resolve "$sandbox/lonely/thing.sh" "$sandbox/lonely")"
expect_eq 'the expected test path for a missing test' \
  "$sandbox/lonely/thing.test.sh" \
  "$(python3 "$scope" --expected "$sandbox/lonely/thing.sh")"
expect_eq 'the expected Go test path' \
  "$project/go/internal/parse/other_test.go" \
  "$(python3 "$scope" --expected "$project/go/internal/parse/other.go")"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
