"""테스트용 가짜 HOME: 운영 체크아웃 4개(진짜 git 저장소)와 그 레포들을 부르는 crontab.

운영 체크아웃 판정은 crontab 과 ~/git/<repo>/.git 에 기대므로, 이 픽스처 없이 돌리면
크론이 도는 호스트에서만 테스트가 맞는다. 테스트 입력의 /home/user 은 가짜 HOME 으로 바꿔 쓴다.
"""
import atexit
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

REAL_HOME = "/home/user"
RUNTIME_REPOS = ("app-live", "app-db", "app-cron", "app-swing")
DISABLED_REPOS = ("app-disabled",)  # crontab 에 주석 줄로만 나온다


def run(*args, repo):
    subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True)


def make():
    home = tempfile.mkdtemp(prefix="guard-home-")
    atexit.register(shutil.rmtree, home, True)
    git = os.path.join(home, "git")
    for r in RUNTIME_REPOS + DISABLED_REPOS:
        d = os.path.join(git, r)
        os.makedirs(d)
        run("init", "-q", "-b", "main", repo=d)
        Path(d, "README.md").write_text("x\n")
        os.makedirs(os.path.join(d, "src"))
        Path(d, "src", "x.py").write_text("x\n")
        run("add", ".", repo=d)
        # 임시 저장소라 전역 훅(커밋 신원 허용 목록)은 끈다. HEAD~1 이 있어야 하는 케이스가 있어 커밋은 둘.
        for m in ("init", "second"):
            run("-c", "core.hooksPath=/dev/null", "-c", "user.name=t", "-c", "user.email=t@example.com",
                "commit", "-q", "--allow-empty", "-m", m, repo=d)
    cron = os.path.join(home, "crontab.txt")
    with open(cron, "w") as f:
        f.write(f"# [DISABLED] 30 18 * * 1-5 cd {git}/app-disabled && ./run.sh\n")
        for r in RUNTIME_REPOS:
            f.write(f"0 8 * * 1-5 cd {git}/{r} && ./run.sh\n")
    env = dict(os.environ, HOME=home, GUARD_TEST_CRONTAB=cron)
    return home, env


def sub(s, home):
    return s.replace(REAL_HOME, home) if isinstance(s, str) else s
