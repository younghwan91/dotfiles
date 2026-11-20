# shellcheck shell=bash
# 공통: 커밋 신원 검사 (pre-commit / pre-push 가 source 한다)
#
# 값은 install.sh 가 프로필에 따라 링크한다:
#   ~/.config/dotfiles/profile      vanilla | personal  (없으면 vanilla)
#   ~/.config/git/allowed-emails    허용할 author/committer 메일, 줄당 하나
#   ~/.config/git/blocked-domains   커밋 메시지에 있으면 push 를 막을 도메인, 줄당 하나
# vanilla 는 값 파일이 없으면 그 검사를 건너뛴다. personal 은 허용 목록이 없으면 막는다.
ALLOW_FILE="${GIT_IDENTITY_ALLOWLIST:-$HOME/.config/git/allowed-emails}"
BLOCK_FILE="$HOME/.config/git/blocked-domains"
DOTFILES_PROFILE=$(cat "$HOME/.config/dotfiles/profile" 2>/dev/null || echo vanilla)

die() {
  echo "" >&2
  echo "  ⛔ Commit identity blocked" >&2
  echo "" >&2
  echo "     $1" >&2
  echo "" >&2
  echo "     Allowlist: $ALLOW_FILE" >&2
  echo "     To fix:    set user.email to an address in the allowlist" >&2
  echo "" >&2
  exit 1
}

# 0 = 허용 목록으로 검사한다, 1 = 건너뛴다(vanilla 에 허용 목록 없음)
identity_check_on() {
  [ -f "$ALLOW_FILE" ] && return 0
  # 링크는 있는데 대상이 없다 = 레포가 옮겨졌거나 install.sh 를 다시 안 돌렸다. 조용히 넘기지 않는다.
  [ -L "$ALLOW_FILE" ] && die "allowlist link is broken: $ALLOW_FILE — run install.sh"
  [ "$DOTFILES_PROFILE" = personal ] && die "personal profile but no allowlist at $ALLOW_FILE — run install.sh"
  return 1
}

is_allowed() {  # $1 = 이메일
  grep -qxF "$1" "$ALLOW_FILE"
}

# 막을 도메인들을 하나의 정규식으로. 파일이 없으면 빈 문자열.
blocked_domain_re() {
  [ -f "$BLOCK_FILE" ] || return 0
  { grep -Ev '^[[:space:]]*(#|$)' "$BLOCK_FILE" || true; } | sed 's/\./\\./g' | paste -sd'|' -
}
