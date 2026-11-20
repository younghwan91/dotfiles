# shellcheck shell=bash
# push 가 끝나면 다른 PC 에서 pull-all 을 돌린다 — pre-push 에서 부른다.
#
# 양쪽 PC 에서 번갈아 작업하니 매번 "풀올"을 손으로 치던 것을 없앤다.
# git 에는 post-push 훅이 없어서, pre-push 끝에서 백그라운드로 띄운 뒤
# 원격 ref 가 실제로 푸시한 커밋이 될 때까지 기다렸다가(푸시 실패면 아무것도 안 함) 실행한다.
#
# 상대 PC 는 git 설정 `sync.peers = host1 host2` (~/.gitconfig.local) 로 정한다. 없으면 상대 PC 동기화는 없다.
# pull-all 은 fast-forward 만 한다 — 수정 중·갈라진·upstream 없는 레포는 건드리지 않고 보고만 한다.
# 로그: ~/.cache/push-sync.log
#
# 2026-10-05 — "배포 = 푸시" 를 끝까지 밀었다:
# - pull 뒤에 **cron-install** 도 돈다(상대 PC 와 푸시한 PC 둘 다). 전엔 크론 파일을 바꿔
#   푸시해도 설치는 다음 07:50 까지 기다렸고, 자기 호스트의 크론을 바꿔 푸시하면 아무도 안
#   설치했다. cron-install 은 멱등이고 바뀐 게
#   없으면 아무것도 안 한다.
# - 실패(2분 내 원격 미반영·상대 접속 불가·CI 보류로 끝까지 못 받음)는 로그에만 남지 않고
#   알림으로 간다 — git 설정 `sync.alert` 가 가리키는 스크립트(`<script> <level> <title>`, 본문은
#   stdin)를 부른다. 설정이 없거나 실행할 수 없으면 조용히 로그만 남긴다.

push_sync_peers() {
  local peers
  peers=$(git config --get sync.peers 2>/dev/null)
  # 상대 PC 가 없으면 빈 값이고, push_sync_after 는 그래도 자기 호스트 cron-install 은 돌린다.
  printf '%s' "$peers"
}

# push_sync_alert <level> <title>   (본문은 stdin)
push_sync_alert() {
  local a; a=$(git config --get sync.alert 2>/dev/null); a=${a/#\~/$HOME}
  if [ -z "$a" ] || [ ! -x "$a" ]; then
    echo "  (no alert.sh — logging only: $2)"
    cat >/dev/null
    return 0
  fi
  "$a" "$@" 2>&1 | sed 's/^/  /'
  return 0
}

# push_sync_after <원격> <원격 ref> <sha> [<원격 ref> <sha> ...]
push_sync_after() {
  [ "${PUSH_SYNC_SKIP:-0}" = "1" ] && return 0
  # 상대 PC 가 없어도(단일 호스트) 멈추지 않는다 — 푸시한 호스트의 cron-install 은 필요하다.
  local peers; peers=$(push_sync_peers)
  local remote=$1; shift
  local log="${HOME}/.cache/push-sync.log"
  mkdir -p "$(dirname "$log")"
  local repo; repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
  (
    # pre-push 는 set -euo pipefail 이다. 그대로 물려받으면 ssh·pull-all 이 1 로 끝나는 순간
    # (보류·건너뜀·접속 실패) 이 백그라운드 작업이 로그 한 줄 없이 죽는다 (2026-09-16).
    set +euo pipefail
    # 푸시가 원격에 반영될 때까지 최대 2분 기다린다. 끝내 안 되면 푸시 실패로 보고 멈춘다.
    local ok=0
    for _ in $(seq 1 60); do
      ok=1
      local args=("$@")
      local k
      for ((k = 0; k < ${#args[@]}; k += 2)); do
        local got; got=$(git ls-remote "$remote" "${args[k]}" 2>/dev/null | cut -f1)
        [ "$got" = "${args[k+1]}" ] || { ok=0; break; }
      done
      [ $ok = 1 ] && break
      sleep 2
    done
    echo "[$(date '+%F %T')] push $repo → $remote"
    if [ $ok != 1 ]; then
      echo "  push not visible on $remote after 2m — skipped peer sync"
      echo "The remote ref never became the pushed commit. The push failed or another push overwrote it right away." \
        | push_sync_alert warn "push-sync: $repo push not visible on $remote within 2m — skipped peer sync"
      exit 0
    fi
    # 푸시한 쪽의 크론도 바뀌었을 수 있다 — 자기 호스트 크론 파일을 고쳐 푸시한 경우,
    # 상대 PC 만 설치하면 정작 여기는 07:50 까지 옛 크론으로 돈다.
    echo "  ▸ $(hostname -s 2>/dev/null || hostname) cron-install"
    "$HOME/git/dotfiles/bin/cron-install" 2>&1 | sed 's/^/    /'
    # 상대 PC 의 pull 정책은 그 PC 가 정한다: ~/.gitconfig.local 의 `sync.pullFlags`
    # (예: --ci-gate — GitHub 체크가 초록인 커밋만 받는다).
    # --ci-gate 로 보류되면 pull-all 이 1 로 끝난다. 체크가 아직 도는 중일 수 있으니
    # 60초 간격으로 최대 10분까지 다시 시도한다. pull 이 어떻게 끝났든 cron-install 은
    # 돌린다(받은 레포가 있으면 설치할 게 있을 수 있다) — 종료코드는 pull-all 의 것을 유지.
    local p
    for p in $peers; do
      echo "  ▸ $p"
      local try out rc
      for try in $(seq 1 10); do
        out=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$p" \
          'f=$(git config --get sync.pullFlags); NO_COLOR=1 "$HOME/git/dotfiles/bin/pull-all" $f; rc=$?;
           "$HOME/git/dotfiles/bin/cron-install" 2>&1 | sed "s/^/  /"; exit $rc' 2>&1)
        rc=$?
        [ $try -gt 1 ] && echo "    (retry $try)"
        printf '%s\n' "$out" | sed 's/^/    /'
        [ $rc -eq 0 ] && break
        printf '%s' "$out" | grep -q "held by CI\|no check runs yet\|running" || break
        sleep 60
      done
      if [ $rc -ne 0 ]; then
        printf '%s\n' "$out" | tail -n 15 \
          | push_sync_alert warn "push-sync: $p failed to pull $repo (rc=$rc) — one of ⏸ held / ✗ / unreachable"
      fi
    done
  ) >>"$log" 2>&1 </dev/null &
  disown 2>/dev/null || true
  return 0
}
