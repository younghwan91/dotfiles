#!/usr/bin/env bash
# ci-local.py 의 공개 레포 가벼운 모드 — 무거운 스텝 판정이 테스트·변이만 고르고 설치·린트는 남기는가.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import importlib.util, sys, types
sys.modules.setdefault("yaml", types.ModuleType("yaml"))   # 판정 함수만 본다 — yaml 은 안 쓴다
spec = importlib.util.spec_from_file_location("ci_local", "git/hooks/ci-local.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
heavy = ["uv run --extra dev pytest -q", "uv run python scripts/verify_merge.py . --scope direct",
         "python scripts/mutation_sample.py", "bash -c 'cd x && pytest'"]
light = ["uv sync --extra dev", "uv run --extra dev ruff check src/ tests/", "uv run python -m compileall -q research",
         "uvx pre-commit run --all-files", "python3 -m py_compile src/a.py"]
bad = [s for s in heavy if not m.is_heavy(s)] + [s for s in light if m.is_heavy(s)]
assert not bad, f"판정이 틀렸다: {bad}"
print("ci-local light: ok")
PY
