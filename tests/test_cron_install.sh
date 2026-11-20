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
