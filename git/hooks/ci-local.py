#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""푸시 전에 그 레포의 .github/workflows/ci.yml 을 로컬에서 그대로 돌린다.

왜 레포별 스크립트가 아니라 ci.yml 을 직접 읽나: 로컬용 명령을 따로 적어두면
ci.yml 과 어긋난다. 원본을 읽으면 CI 를 고치는 순간 로컬도 같이 바뀐다.

충실도를 위해 지키는 것:
- **푸시할 커밋**을 별도 워크트리(.git/ci-local/worktree)에 체크아웃해서 돌린다.
  작업 트리의 미커밋 변경·추적 안 되는 파일(.env 등)이 결과를 가리지 않는다.
- 전용 venv(.git/ci-local/venv-<py>)를 쓴다. 개발용 .venv 를 건드리지 않는다
  (`uv sync` 는 정확 동기화라 개발용 venv 의 추가 패키지를 지운다).
- `pip install` 은 `uv pip install --upgrade` 로 바꾼다. CI 러너는 매번 새로
  설치해서 최신 버전을 받는다 — `ruff>=0.6` 가 CI 에서만 새 규칙으로 터진
  kiwoom-client 사례(2026-09-13)를 로컬에서도 재현하려면 업그레이드가 필요하다.

로컬에서 흉내내지 않는 것(건너뛰었다고 출력한다):
- `services:` 가 필요한 잡(Postgres·Redis 통합 테스트)
- `uses:` 액션 (pre-commit/action 만 `pre-commit run --all-files` 로 대체)
- `uv build`, 해석할 수 없는 `${{ }}` 식이 남은 스텝
- 매트릭스는 파이썬 한 버전만 (3.12 가 있으면 3.12, 없으면 가장 높은 버전)

공개 레포는 가볍게 돈다: GitHub Actions 가 무료로 전체 CI 를 돌리고 ruleset 이 초록일 때만 머지하게 하므로,
로컬에서는 린트·문법 같은 빠른 스텝만 돌리고 무거운 스텝(pytest·변이 검사)은 건너뛴다(`is_heavy`).
50분짜리 pre-push 는 결국 --no-verify 로 우회된다(sector-flow, 2026-11-21). 공개 레포에서도 전체를 원하면 CI_LOCAL_FULL=1.

사용: ci-local.py [<commit>]   (기본 HEAD)
우회: SKIP_CI_LOCAL=1 git push   또는   git push --no-verify
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yaml

G, Y, RD, D, B, R = "\033[32m", "\033[33m", "\033[31m", "\033[2m", "\033[1m", "\033[0m"
EXPR = re.compile(r"\$\{\{\s*([^}]+?)\s*\}\}")


def git(*args: str, cwd: Path | None = None) -> str:
    return subprocess.run(
        ["git", *args], cwd=cwd, check=True, capture_output=True, text=True
    ).stdout.strip()


def say(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def pick_python(wf: dict) -> str:
    cands: list[str] = []
    env_py = (wf.get("env") or {}).get("PYTHON_VERSION")
    if env_py:
        cands.append(str(env_py))
    for job in (wf.get("jobs") or {}).values():
        mx = ((job.get("strategy") or {}).get("matrix") or {}).get("python-version")
        if isinstance(mx, list):
            cands += [str(v) for v in mx]
        for st in job.get("steps") or []:
            v = (st.get("with") or {}).get("python-version")
            if v and "${{" not in str(v):
                cands.append(str(v))
    if not cands:
        return "3.12"
    if "3.12" in cands:
        return "3.12"
    return max(cands, key=lambda s: tuple(int(p) for p in s.split(".") if p.isdigit()))


def substitute(text: str, ctx: dict[str, str]) -> str | None:
    """${{ matrix.python-version }} / ${{ env.X }} 만 푼다. 못 풀면 None."""
    def repl(m: re.Match) -> str:
        key = m.group(1)
        if key in ctx:
            return ctx[key]
        raise KeyError(key)

    try:
        return EXPR.sub(repl, text)
    except KeyError:
        return None


def translate(script: str) -> str | None:
    """설치 명령을 로컬 venv 용으로 바꾼다. 스텝 전체를 건너뛸 거면 None."""
    out = []
    for line in script.splitlines():
        s = line.strip()
        if re.search(r"pip install (--upgrade|-U) pip\b", s):
            continue
        if re.match(r"uv python install\b", s) or re.match(r"uv build\b", s):
            continue
        line = re.sub(r"(python -m )?\bpip install\b", "uv pip install --upgrade", line)
        out.append(line)
    body = "\n".join(out).strip()
    return body or None


_LOCK: list = []  # 잡고 있는 ci-local 잠금 파일(GC 로 닫히지 않게)
_WT: list[tuple[Path, Path]] = []   # (레포, 전용 워크트리) — 끝나면 지운다


def cleanup() -> None:
    """전용 워크트리를 남겨 두면 Orca·`git worktree list` 에 레포마다 detached HEAD 가 하나씩 떴다(2026-10-25).
    venv 는 워크트리 밖(.git/ci-local/venv-<py>)이라 지워도 다음 푸시가 크게 느려지지 않는다."""
    for top, wt in _WT:
        subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=top, capture_output=True)
        shutil.rmtree(wt, ignore_errors=True)
        subprocess.run(["git", "worktree", "prune"], cwd=top, capture_output=True)


#: 공개 레포에서 로컬로 돌리지 않는 무거운 스텝 — GitHub CI 가 돈다. 커버리지 스텝은 건너뛴 pytest 의 결과를 읽으니 같이 뺀다.
HEAVY = re.compile(r"\b(pytest|verify_merge|mutation_sample|mutmut|diff_coverage|diff-cover|coverage)\b")


def is_heavy(script: str) -> bool:
    """테스트 실행·변이 검사처럼 오래 걸리는 스텝인가(설치·린트·문법 검사는 아니다)."""
    return bool(HEAVY.search(script))


def is_public(top: Path) -> bool:
    """레포가 GitHub 공개 레포인가. gh 가 없거나 실패하면 False(전체를 돈다 — 안전한 쪽)."""
    try:
        out = subprocess.run(["gh", "repo", "view", "--json", "visibility", "-q", ".visibility"],
                             cwd=top, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return out.returncode == 0 and out.stdout.strip() == "PUBLIC"


def main() -> int:
    if os.environ.get("SKIP_CI_LOCAL"):
        say(f"{D}ci-local: skipped via SKIP_CI_LOCAL{R}")
        return 0

    sha = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    top = Path(git("rev-parse", "--show-toplevel"))
    light = not os.environ.get("CI_LOCAL_FULL") and is_public(top)
    if light:
        say(f"{D}ci-local: 공개 레포 — 빠른 스텝만 돈다(pytest·변이 검사는 GitHub CI). 전체는 CI_LOCAL_FULL=1{R}")
    common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir"))
    # 훅은 GIT_DIR 등을 물려받는다. 링크된 워크트리에서 푸시하면 그게 그 워크트리의 gitdir 이라,
    # 아래 `git checkout --detach ... cwd=wt` 가 cwd(전용 워크트리)가 아니라 **푸시한 워크트리의
    # HEAD 를** 푸시 대상 sha 로 떼어 놓았다 — 브랜치에서 일하던 워크트리가 조용히 detached 가 되고,
    # 그 뒤 amend 는 브랜치를 안 움직여 같은 커밋만 거듭 검사됐다(실제로 있었던 일).
    # 저장소 위치는 위에서 다 얻었으니 이후 git 호출은 전부 cwd 로 찾게 지운다.
    for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_PREFIX",
              "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"):
        os.environ.pop(k, None)
    sha = git("rev-parse", sha)

    wf_text = None
    for name in ("ci.yml", "ci.yaml"):
        try:
            wf_text = git("show", f"{sha}:.github/workflows/{name}", cwd=top)
            break
        except subprocess.CalledProcessError:
            continue
    if wf_text is None:
        return 0  # CI 없는 레포

    wf = yaml.safe_load(wf_text) or {}
    py = pick_python(wf)
    base = common / "ci-local"
    base.mkdir(exist_ok=True)
    # 링크된 워크트리는 .git(common) 을 같이 쓴다 → ci-local/worktree·venv 도 하나뿐이다. 잠금 없이
    # 두 워크트리에서 동시에 푸시하면 서로의 체크아웃을 덮어써 엉뚱한 파일로 테스트가 깨졌다
    # (2026-10-26 cerebellum, 에이전트 8개 병렬). 프로세스가 끝나면 잠금은 저절로 풀린다.
    import fcntl
    lock = open(base / "lock", "w")  # noqa: SIM115 — 프로세스 수명 동안 쥔다
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        say(f"  {D}다른 워크트리의 ci-local 이 도는 중 — 끝날 때까지 기다린다{R}")
        fcntl.flock(lock, fcntl.LOCK_EX)
    _LOCK.append(lock)
    wt = base / "worktree"
    venv = base / f"venv-{py}"
    logdir = base / "logs"
    logdir.mkdir(exist_ok=True)

    say(f"\n{B}▶ ci-local{R} {top.name} @ {sha[:8]}  {D}(python {py}, from ci.yml · bypass: git push --no-verify){R}")

    # 푸시할 커밋을 전용 워크트리에 — 끝나면 cleanup() 이 지운다(남은 게 있으면 재사용)
    git("worktree", "prune", cwd=top)
    if not (wt / ".git").exists():
        shutil.rmtree(wt, ignore_errors=True)
        git("worktree", "add", "--detach", "--force", str(wt), sha, cwd=top)
    else:
        git("checkout", "--detach", "--force", sha, cwd=wt)
        git("clean", "-fdxq", "-e", ".pytest_cache", "-e", ".ruff_cache",
            "-e", ".mypy_cache", cwd=wt)
    _WT.append((top, wt))
    # sparse checkout 인 메인 체크아웃(예: 몇 파일만 받는 운영 체크아웃)
    # 에서 만든 워크트리는 그 sparse 패턴을 **물려받는다**. 그러면 CI 가
    # docker/requirements.txt 를 못 찾아 Install 에서 죽고 푸시가 막힌다(2026-10-04 실측,
    # 손으로 disable 해서 넘겼다). extensions.worktreeConfig 가 켜져 있어 이 설정은
    # 워크트리별이다 — 여기서 꺼도 메인 체크아웃은 그대로 sparse 다. CI 는 늘 전체 트리.
    sparse = subprocess.run(["git", "config", "--worktree", "--get", "core.sparseCheckout"],
                            cwd=wt, capture_output=True, text=True).stdout.strip()
    if sparse == "true":
        say(f"  {D}worktree inherited sparse checkout — fetching the full tree for CI{R}")
        git("sparse-checkout", "disable", cwd=wt)
    subprocess.run(["git", "submodule", "update", "--init", "--recursive", "-q"],
                   cwd=wt, capture_output=True)

    if not (venv / "bin" / "python").exists():
        say(f"  {D}creating venv: {venv}{R}")
        subprocess.run(["uv", "venv", "--seed", "-q", "--python", py, str(venv)], check=True)

    base_env = {k: v for k, v in os.environ.items()
                if k not in ("VIRTUAL_ENV", "UV_PROJECT_ENVIRONMENT", "GIT_DIR",
                             "GIT_WORK_TREE", "GIT_INDEX_FILE")}
    base_env.update({
        "CI": "true",
        "VIRTUAL_ENV": str(venv),
        "UV_PROJECT_ENVIRONMENT": str(venv),
        "UV_PYTHON": str(venv / "bin" / "python"),
        "PATH": f"{venv / 'bin'}:{os.environ.get('PATH', '')}",
        "PRE_COMMIT_HOME": str(Path.home() / ".cache" / "pre-commit"),
        # CI 러너엔 전역 git 설정이 없다. 여기 core.hooksPath(신원 훅)가 새면 테스트가
        # 임시 레포에 커밋하다 막힌다(테스트가 임시 레포를 만드는 경우).
        "GIT_CONFIG_GLOBAL": "/dev/null",
    })
    wf_env = {str(k): str(v) for k, v in (wf.get("env") or {}).items()}

    ran: set[str] = set()      # 잡 사이에 똑같은 설치 스텝은 한 번만
    failures: list[str] = []
    skipped: list[str] = []

    for job_id, job in (wf.get("jobs") or {}).items():
        label = str(job.get("name") or job_id).replace("${{ matrix.python-version }}", py)
        if job.get("services"):
            skipped.append(f"{label} (needs services)")
            continue
        job_env = {**wf_env, **{str(k): str(v) for k, v in (job.get("env") or {}).items()}}
        ctx = {"matrix.python-version": py, **{f"env.{k}": v for k, v in job_env.items()}}

        for i, st in enumerate(job.get("steps") or []):
            first = str(st.get("run") or "").strip().splitlines()[:1]
            name = st.get("name") or st.get("uses") or (first[0][:60] if first else f"step {i}")
            uses = st.get("uses") or ""
            if uses:
                if "pre-commit/action" in uses:
                    script = "uvx pre-commit run --all-files --show-diff-on-failure"
                else:
                    continue
            else:
                raw = st.get("run")
                if not raw:
                    continue
                sub = substitute(str(raw), ctx)
                if sub is None:
                    skipped.append(f"{label} › {name} (unresolved expression)")
                    continue
                script = translate(sub)
                if script is None:
                    continue

            if light and is_heavy(script):
                skipped.append(f"{label} › {name} (공개 레포 — GitHub CI 가 돈다)")
                continue

            is_install = bool(re.search(r"\b(uv sync|uv pip install)\b", script))
            if is_install and script in ran:
                continue

            step_env = {**base_env, **job_env,
                        **{str(k): str(v) for k, v in (st.get("env") or {}).items()}}
            cwd = wt / st["working-directory"] if st.get("working-directory") else wt
            log = logdir / f"{job_id}-{i}.log"
            t0 = time.time()
            with open(log, "w") as fh:
                rc = subprocess.run(["bash", "-eo", "pipefail", "-c", script],
                                    cwd=cwd, env=step_env, stdout=fh,
                                    stderr=subprocess.STDOUT).returncode
            dt = time.time() - t0
            if rc == 0:
                ran.add(script)
                say(f"  {G}✓{R} {label} › {name} {D}({dt:.0f}s){R}")
                continue

            if st.get("continue-on-error") is True:
                # CI 에서도 실패를 보고만 하는 스텝이다 — 막지 않는다
                say(f"  {Y}⚠{R} {label} › {name} {D}(failed but continue-on-error, log {log}){R}")
                continue

            say(f"  {RD}✗ {label} › {name}{R} {D}({dt:.0f}s, log {log}){R}")
            tail = log.read_text(errors="replace").splitlines()[-40:]
            for line in tail:
                say(f"    {D}│{R} {line}")
            failures.append(f"{label} › {name}")
            break  # CI 처럼 잡은 첫 실패에서 멈추고 다음 잡으로

    for s in skipped:
        say(f"  {Y}–{R} {D}skipped: {s}{R}")
    if failures:
        say(f"\n  {RD}{B}⛔ ci-local: {len(failures)} failure(s) — push blocked.{R}")
        for f in failures:
            say(f"     - {f}")
        say(f"  {D}fix and push again, or if urgent: git push --no-verify{R}\n")
        return 1
    say(f"  {G}{B}✓ ci-local passed{R}\n")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
    finally:
        cleanup()
    sys.exit(rc)
