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

# 잘못된 스케줄이 하나라도 있으면 아무것도 설치하지 않고 1 로 끝난다 — 지금 crontab 은 그대로
before=$(cat "$FAKE_CRONTAB")
mkdir -p "$T/git/broken/deploy"; echo '61 7 * * * echo bad-minute' > "$T/git/broken/deploy/crontab.h1"
if PATH="$T/bin:$PATH" python3 "$REPO/bin/cron-install" > "$T/out.txt" 2>&1; then
  echo "FAIL cron_install_accepted_bad_line"; exit 1
elif [ "$before" != "$(cat "$FAKE_CRONTAB")" ] || ! grep -q "broken" "$T/out.txt"; then
  echo "FAIL cron_install_changed_crontab_or_silent"; sed 's/^/    /' "$T/out.txt"; exit 1
else
  echo "test_cron_install: rejects bad line pass"
fi

rm -rf "$T/git/broken"  # 위 테스트가 둔 잘못된 줄
# --drop-dead: 울타리 밖 줄 중 없는 경로를 가리키는 줄과 바로 위 주석만 지운다 — 관리 블록·산 줄·출력 파일은 그대로
mkdir -p "$T/alive"; : > "$T/alive/run.sh"
{ echo "# keep this header"; echo; echo "# about the dead job"; echo "# second comment line"; echo "30 16 * * 1-5 $T/gone/collect.sh"; echo;
  echo "30 12 * * * cd $T/renamed && node watch.js >> data/w.log 2>&1 # watch"; echo "0 1 * * * $T/alive/run.sh >> $T/nolog/x.log 2>&1"; cat "$FAKE_CRONTAB"; } > "$T/c" && mv "$T/c" "$FAKE_CRONTAB"
blocks_before=$(grep -c '^# >>> managed' "$FAKE_CRONTAB")
PATH="$T/bin:$PATH" python3 "$REPO/bin/cron-install" --drop-dead --diff > "$T/out.txt" 2>&1
if ! grep -q 'collect.sh' "$FAKE_CRONTAB"; then echo "FAIL drop_dead_diff_changed_crontab"; exit 1; fi
PATH="$T/bin:$PATH" python3 "$REPO/bin/cron-install" --drop-dead > "$T/out.txt" 2>&1
if grep -qE 'collect.sh|about the dead job|second comment|renamed' "$FAKE_CRONTAB" || ! grep -q 'keep this header' "$FAKE_CRONTAB" \
   || ! grep -q "$T/alive/run.sh" "$FAKE_CRONTAB" || [ "$(grep -c '^# >>> managed' "$FAKE_CRONTAB")" != "$blocks_before" ] \
   || [ "$(grep -c '관리 밖 줄 지움' "$T/out.txt")" != 2 ]; then
  echo "FAIL cron_install_drop_dead"; sed 's/^/    /' "$T/out.txt" "$FAKE_CRONTAB" | head -30; exit 1
fi
echo "test_cron_install: drop-dead pass"
