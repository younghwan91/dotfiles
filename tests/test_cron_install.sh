#!/usr/bin/env bash
# cron-install 이 <레포>/personal/deploy/crontab.<호스트> 도 읽고, 블록 이름은 레포 이름인지.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" CRON_REPOS_ROOT="$T/git" CRON_HOST=h1 FAKE_CRONTAB="$T/crontab.txt"
mkdir -p "$HOME" "$T/bin" "$T/git/dotfiles/personal/deploy"
: > "$FAKE_CRONTAB"
cat > "$T/bin/crontab" <<'SH'
#!/usr/bin/env bash
case "$1" in -l) cat "$FAKE_CRONTAB" ;; -) cat > "$FAKE_CRONTAB" ;; *) exit 1 ;; esac
SH
chmod +x "$T/bin/crontab"
echo '0 7 * * * echo hi' > "$T/git/dotfiles/personal/deploy/crontab.h1"
PATH="$T/bin:$PATH" python3 "$REPO/bin/cron-install" > "$T/out.txt" 2>&1
if grep -q '^# >>> managed: dotfiles (personal/deploy/crontab.h1)' "$FAKE_CRONTAB" && grep -q '^0 7 \* \* \* echo hi$' "$FAKE_CRONTAB"; then
  echo "test_cron_install: 1/1 pass"
else
  echo "FAIL personal_crontab_block_name"; sed 's/^/    /' "$T/out.txt" "$FAKE_CRONTAB"; exit 1
fi

# 다시 돌려도 crontab 이 그대로여야 한다 — 블록 뒤에 관리 밖 줄이 있으면 실행마다 빈 줄이 쌓였다
for r in other third fourth; do mkdir -p "$T/git/$r/deploy"; echo "5 8 * * * echo $r" > "$T/git/$r/deploy/crontab.h1"; done
PATH="$T/bin:$PATH" python3 "$REPO/bin/cron-install" > "$T/out.txt" 2>&1
{ echo "# header kept by hand"; cat "$FAKE_CRONTAB"; echo "30 12 * * * echo unmanaged-after-blocks"; } > "$T/c" && mv "$T/c" "$FAKE_CRONTAB"
for i in 1 2 3; do PATH="$T/bin:$PATH" python3 "$REPO/bin/cron-install" > "$T/out.txt" 2>&1; cp "$FAKE_CRONTAB" "$T/run$i"; done
if cmp -s "$T/run2" "$T/run3" && ! grep -Pzq '\n\n\n' "$T/run3" && grep -q 'unmanaged-after-blocks' "$T/run3"; then
  echo "test_cron_install: idempotent pass"
else
  echo "FAIL cron_install_idempotent"; diff "$T/run2" "$T/run3" | head; cat -A "$T/run3" | head -20; exit 1
fi
