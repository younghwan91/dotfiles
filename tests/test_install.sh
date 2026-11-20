#!/usr/bin/env bash
# install.sh --profile 을 임시 HOME 에서 검사한다. 서비스(systemctl·orca)는 건너뛴다.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export INSTALL_SKIP_SERVICES=1 GIT_CONFIG_NOSYSTEM=1
# ci-local 훅은 GIT_CONFIG_GLOBAL=/dev/null 을 넣는다 — 임시 HOME 의 ~/.gitconfig 를 읽게 지운다
unset GIT_CONFIG_GLOBAL
pass=0 fail=0 tmps=()
trap 'rm -rf "${tmps[@]}"' EXIT

# 가짜 personal 레포 — 실제 개인 값은 별도 비공개 레포라 여기 없다
P=$(mktemp -d); tmps+=("$P"); export DOTFILES_PERSONAL=$P
mkdir -p "$P/git" "$P/claude/agents"
printf '[user]\n\tname = t\n\temail = t@example.com\n' > "$P/git/gitconfig"
echo t@example.com > "$P/git/allowed-emails"; : > "$P/git/blocked-domains"
echo x > "$P/claude/CLAUDE.md"; echo x > "$P/claude/agents/quant-reviewer.md"

fresh() { export HOME; HOME=$(mktemp -d); tmps+=("$HOME"); export BIN_DIR="$HOME/bin"; }
inst() { "$REPO/install.sh" "$@" </dev/null >"$HOME/out.txt" 2>&1; }
personal_links() { find "$HOME" -type l -lname "$P/*" | wc -l; }
ok() { pass=$((pass + 1)); }
no() { fail=$((fail + 1)); echo "FAIL $1"; sed 's/^/    /' "$HOME/out.txt" | tail -5; }
points() { [ "$(readlink "$1")" = "$2" ]; }

fresh; inst --profile vanilla
if [ $? -eq 0 ] && [ "$(personal_links)" -eq 0 ] && [ "$(cat "$HOME/.config/dotfiles/profile")" = vanilla ]; then ok; else no vanilla_no_personal_links; fi

fresh; inst --profile personal
if [ $? -eq 0 ] && points "$HOME/.config/git/allowed-emails" "$P/git/allowed-emails" \
   && points "$HOME/.config/git/blocked-domains" "$P/git/blocked-domains" \
   && points "$HOME/.config/git/profile.gitconfig" "$P/git/gitconfig" \
   && points "$HOME/.claude/agents/quant-reviewer.md" "$P/claude/agents/quant-reviewer.md" \
   && points "$HOME/.claude/CLAUDE.personal.md" "$P/claude/CLAUDE.md"; then ok; else no personal_links; fi

inst --profile vanilla
if [ $? -eq 0 ] && [ "$(personal_links)" -eq 0 ]; then ok; else no switch_to_vanilla_removes_personal_links; fi

fresh; inst; rc=$?
if [ $rc -eq 2 ] && grep -q -- '--profile' "$HOME/out.txt"; then ok; else no "no_tty_no_profile (rc=$rc)"; fi

fresh; inst --profile personal; inst; rc=$?
if [ $rc -eq 0 ] && points "$HOME/.config/git/allowed-emails" "$P/git/allowed-emails"; then ok; else no saved_profile_reused; fi

fresh; git config --file "$HOME/.gitconfig.local" user.email a@b.c; git config --file "$HOME/.gitconfig.local" user.name a
inst --profile vanilla
if [ $? -eq 0 ] && ! grep -q '신원이 없다' "$HOME/out.txt"; then ok; else no vanilla_identity_in_local_detected; fi

fresh; mkdir -p "$HOME/.config/git" "$HOME/.claude/agents"
ln -s "$REPO/git/allowed-emails" "$HOME/.config/git/allowed-emails"   # 옛 위치, 지금은 없음
ln -s "$REPO/claude/agents/quant-reviewer.md" "$HOME/.claude/agents/quant-reviewer.md"
inst --profile vanilla
if [ $? -eq 0 ] && [ ! -L "$HOME/.config/git/allowed-emails" ] && [ ! -L "$HOME/.claude/agents/quant-reviewer.md" ]; then ok; else no vanilla_prunes_stale_links; fi

# personal 이 없으면 DOTFILES_PERSONAL_REPO 를 clone 해서 링크한다
fresh; src=$(mktemp -d); tmps+=("$src")
cp -r "$P/." "$src/" && git -C "$src" init -q && git -C "$src" add -A \
  && git -C "$src" -c user.name=t -c user.email=t@example.com commit -qm init
DOTFILES_PERSONAL="$HOME/p" DOTFILES_PERSONAL_REPO="$src" inst --profile personal
if [ $? -eq 0 ] && [ -d "$HOME/p/.git" ] && points "$HOME/.config/git/allowed-emails" "$HOME/p/git/allowed-emails"; then ok; else no personal_cloned_when_missing; fi

# bin/ 의 실행 파일만 링크하고, 부산물(__pycache__)을 가리키던 옛 링크는 걷는다
fresh; mkdir -p "$BIN_DIR"; ln -s "$REPO/bin/__pycache__" "$BIN_DIR/__pycache__"
inst --profile vanilla
if [ $? -eq 0 ] && [ -L "$BIN_DIR/pull-all" ] && [ ! -e "$BIN_DIR/__pycache__" ] && [ ! -L "$BIN_DIR/__pycache__" ]; then ok; else no bin_links_executables_only; fi

# zshrc 는 프로필 파일이 없으면 DOTFILES_PROFILE 을 비워 둔다 — setup 스크립트가 그걸 선택으로 오인하면 안 된다
if command -v zsh >/dev/null; then
  fresh
  got=$(HOME="$HOME" zsh -fc "$(sed -n '/install.sh 가 고른/,/export DOTFILES DOTFILES_OS/p' "$REPO/zsh/zshrc"); print -r -- \"[\$DOTFILES_PROFILE]\"" 2>&1)
  if [ "$got" = "[]" ]; then ok; else echo "    got: $got" > "$HOME/out.txt"; no zshrc_no_profile_leaves_empty; fi
fi

echo "test_install: $pass/$((pass + fail)) pass"
[ $fail -eq 0 ]
