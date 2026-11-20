#!/usr/bin/env bash
# actionlint — .github/workflows 의 문법·표현식·run 스크립트(shellcheck 포함)를 본다.
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v actionlint >/dev/null; then a=(actionlint)
elif command -v uvx >/dev/null; then a=(uvx -q --from actionlint-py actionlint)
else a=(pipx run --spec actionlint-py actionlint); fi
"${a[@]}" .github/workflows/*.yml
echo "actionlint: workflows clean"
