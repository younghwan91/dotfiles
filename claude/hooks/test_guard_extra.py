"""v3 추가 회귀 — 재검토(v2)에서 통과돼 버린 실수형·고피해 사례 + 오탐 완화."""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
G = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "guard.py")
sys.path.insert(0, HERE)
import _guard_fixture as fx
# 가짜 HOME + crontab: guard 가 import 될 때 HOME 을 읽으므로 그 전에 바꾼다
FAKE, _env = fx.make()
os.environ.update(HOME=FAKE, GUARD_TEST_CRONTAB=_env["GUARD_TEST_CRONTAB"])
spec = importlib.util.spec_from_file_location("g", G)
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
W = fx.sub("/home/user/git/app-swing", FAKE)
cases = [
    ("DENY", "python3 -c 'import os;print(os.environ[\"APP_DB\"])'"),
    ("ok", "python3 -c 'import os;print(os.environ[\"TIMESCALE_HOST\"])'"),
    ("DENY", "docker exec tsdb env"),
    ("DENY", "docker exec tsdb printenv POSTGRES_PASSWORD"),
    ("ok", "docker exec tsdb psql -U app -c 'select 1'"),
    ("DENY", "set -o xtrace; . ./.env"),
    ("DENY", "set -a; . ./.env; set +a; declare -p APP_DB"),
    ("DENY", "psql \"$DB\" -c \"DROP INDEX x; drop extension timescaledb cascade\""),
    ("DENY", "psql \"$DB\" -c \"DROP VIEW foo CASCADE\""),
    ("DENY", "psql \"$DB\" -c \"DELETE FROM daily_bars\""),
    ("ok", "psql \"$DB\" -c \"DELETE FROM daily_bars WHERE date='2026-01-01'\""),
    ("ok", "psql \"$DB\" -c 'DROP INDEX IF EXISTS tmp_idx'"),
    ("DENY", "find ~ -delete"),
    ("DENY", "find ~/git -mindepth 1 -delete"),
    ("ok", "find /tmp/x -name '*.pyc' -delete"),
    ("ok", "find . -name __pycache__ -type d"),
    ("DENY", "docker compose rm -v"),
    ("ok", "docker compose ps"),
    ("DENY", "git -C ~/git/app-live reset --hard origin/x"),
    ("ok", "git -C ~/git/app-live reset --hard origin/main"),
    ("ok", "git -C ~/git/app-live reset --hard HEAD~1"),
    ("ok", "git -C ~/git/app-live merge x"),  # main 위 머지는 배포 흐름
    ("ok", "git -C ~/git/app-live merge --abort"),
    ("DENY", "git -C ~/git/app-live pull origin research"),
    ("ok", "git -C ~/git/app-live pull --ff-only"),
    ("ok", "git -C ~/git/app-live pull origin main"),
    ("ok", "git -C ~/git/.harness-wt/app-live merge x"),
    ("DENY", "git reset --hard origin/feature-x"),  # cwd W 가 운영 체크아웃
    ("DENY", "echo $TIMESCALE_PW"),
    ("ok", "echo $TIMESCALE_DB"),
    ("ok", "echo $TIMESCALE_HOST:$TIMESCALE_PORT"),
    ("DENY", "for r in a b; do grep APP_DB ~/git/$r/.env; done"),
    ("DENY", "(cd ~/git/app-live; git checkout -b x)"),
    ("DENY", "cat .env | head -5"),
    ("DENY", "cat .env | sort"),
    ("DENY", "set -a; . ./.env; set +a; env | sort"),
    ("DENY", "echo \"DB: $(grep APP_DB .env)\""),
    ("DENY", "bash -c 'cat .env'"),
    ("DENY", "sh -c \"git push -f origin main\""),
    ("DENY", "ssh h \"cat .env\""),
    ("DENY", "python3 -c \"print(open('.env').read())\""),
    ("DENY", "echo \"${APP_DB%%@*}\""),
    ("DENY", "cat /proc/1234/environ | tr '\\0' '\\n'"),
    ("DENY", "grep -oE '^[A-Z_]+=.*' .env"),
    ("DENY", "crontab -ri"),
]
bad = 0
for e, c in cases:
    r = g.check_bash(fx.sub(c, FAKE), W)
    got = "DENY" if r else "ok"
    if got != e:
        bad += 1
        print("FAIL", e, got, c, r)
# 꺼 둔(주석) 크론 줄의 레포는 운영 체크아웃이 아니다 (HOME 은 픽스처 — 두 레포가 다 있다)
H = os.path.expanduser("~/git")
tab = f"# [DISABLED] 30 18 * * 1-5 cd {H}/app-disabled && x\n55 8 * * 1-5 cd {H}/app-live && y\n"
rt = g.runtime_names(tab)
if f"{H}/app-disabled" in rt:
    bad += 1
    print("FAIL commented cron line counted as runtime")
if f"{H}/app-live" not in rt:
    bad += 1
    print("FAIL active cron line missed")
print(f"{len(cases) - bad}/{len(cases)} v3-extra pass")
sys.exit(1 if bad else 0)
