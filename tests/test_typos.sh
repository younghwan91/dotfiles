#!/usr/bin/env bash
# typos — 코드·주석·문서의 영어 오타. 오탐 허용은 _typos.toml.
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v typos >/dev/null; then t=(typos); elif command -v uvx >/dev/null; then t=(uvx -q typos); else t=(pipx run --spec typos typos); fi
"${t[@]}"
echo "typos: clean"
