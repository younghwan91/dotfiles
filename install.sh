#!/usr/bin/env bash
# 이 머신에 dotfiles 를 설치한다. 다시 돌려도 안전하다.
#
#   ./install.sh --profile vanilla|personal
#                              이 OS(darwin / linux / wsl)용 설정을 링크. vanilla = 범용만,
#                              personal = 범용 + personal/ (내 신원·에이전트·크론 값). personal/ 는 이 레포에
#                              없고 별도 비공개 레포다 — 없으면 origin 옆의 <이름>-personal 레포를 clone 한다
#                              (DOTFILES_PERSONAL_REPO 로 바꿀 수 있음, 위치는 DOTFILES_PERSONAL).
#                              고른 값은 ~/.config/dotfiles/profile 에 저장 — 다음부터는 생략 가능
#   ./install.sh --claude-md   claude/CLAUDE.md 도 Claude Code 전역 지시문으로 링크
#   ./install.sh --brew        macOS: macos/Brewfile 로 `brew bundle` 도 실행
#
# 이미 있는 실제 파일은 심볼릭 링크로 바꾸기 전에 <file>.bak 으로 옮긴다.
# 머신별·비밀 설정은 *.local 파일에 둔다(이 레포에는 절대 넣지 않는다):
#   ~/.zshrc.local  ~/.zshenv.local  ~/.gitconfig.local
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"

with_claude_md=0 with_brew=0 profile=
while [ $# -gt 0 ]; do
  case $1 in
    --claude-md) with_claude_md=1 ;;
    --brew) with_brew=1 ;;
    --profile) profile=${2:-}; shift ;;
    --profile=*) profile=${1#--profile=} ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
  shift
done

# 프로필: 플래그 → 저장값 → (터미널이면) 묻기. 비대화형에서 모르면 멈춘다.
profile_file="$HOME/.config/dotfiles/profile"
[ -z "$profile" ] && [ -f "$profile_file" ] && profile=$(cat "$profile_file")
if [ -z "$profile" ] && [ -t 0 ]; then
  read -r -p "프로필 (vanilla = 범용만 / personal = 범용 + personal/): " profile
fi
case $profile in
  vanilla|personal) ;;
  "") echo "프로필을 모른다 — install.sh --profile vanilla|personal 로 다시 실행" >&2; exit 2 ;;
  *) echo "알 수 없는 프로필: $profile (vanilla | personal)" >&2; exit 2 ;;
esac
mkdir -p "$(dirname "$profile_file")"
echo "$profile" > "$profile_file"

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux)  grep -qi microsoft /proc/version 2>/dev/null && os=wsl || os=linux ;;
  *)      os=other ;;
esac

if [ -t 1 ]; then B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' C=$'\e[36m' D=$'\e[2m' R=$'\e[0m'; else B='' G='' Y='' C='' D='' R=''; fi
echo "${B}${C}▸ dotfiles${R} ${D}os=$os  profile=$profile  repo=${repo/#$HOME/~}${R}"

link() {  # link <레포 기준 원본 | 절대 경로> <대상>
  local src dst=$2
  case $1 in /*) src=$1 ;; *) src="$repo/$1" ;; esac
  [ -e "$src" ] || { echo "  ${Y}없음${R} $1"; return; }
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "  ${D}✓ ${dst/#$HOME/~}${R}"; return
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    if cmp -s "$src" "$dst" 2>/dev/null; then rm -rf "$dst"
    else mv "$dst" "$dst.bak"; echo "  ${Y}백업${R} ${dst/#$HOME/~}.bak"; fi
  fi
  ln -sfn "$src" "$dst"
  echo "  ${G}→${R} ${dst/#$HOME/~}"
}

# ---- 모든 OS ----
bin_dir=${BIN_DIR:-$HOME/.local/bin}
for f in "$repo"/bin/*; do
  # 실행 파일만 — bin/__pycache__ 같은 부산물이 PATH 에 링크된 적이 있다
  [ -f "$f" ] && [ -x "$f" ] && link "bin/$(basename "$f")" "$bin_dir/$(basename "$f")"
done
for l in "$bin_dir"/*; do  # 그런 부산물을 가리키던 옛 링크를 걷는다
  [ -L "$l" ] || continue; t=$(readlink "$l")
  [[ $t == "$repo/bin/"* ]] && { [ ! -f "$t" ] || [ ! -x "$t" ]; } && { rm "$l"; echo "  ${Y}제거${R} ${l/#$HOME/~}"; }
done
link zsh/zshrc  ~/.zshrc
link zsh/zshenv ~/.zshenv
if [ $os = darwin ] && [ -e "$repo/zsh/p10k.darwin.zsh" ]; then link zsh/p10k.darwin.zsh ~/.p10k.zsh
else link zsh/p10k.zsh ~/.p10k.zsh; fi
link git/gitconfig     ~/.gitconfig
link git/hooks         ~/.config/git/hooks
link git/ignore        ~/.config/git/ignore
link vim/vimrc  ~/.vimrc
link npm/npmrc  ~/.npmrc

# Claude Code 상태 줄 — settings.json 의 statusLine 키만 건드린다.
link claude/hud/statusline.sh ~/.claude/hud/statusline.sh
if command -v python3 >/dev/null; then
  python3 - "$HOME/.claude/settings.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
want = {"type": "command", "command": "bash $HOME/.claude/hud/statusline.sh"}
if d.get("statusLine") != want:
    d["statusLine"] = want
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False); f.write("\n")
    print("  → ~/.claude/settings.json statusLine 설정")
PY
fi
if [ $with_claude_md = 1 ]; then link claude/CLAUDE.md ~/.claude/CLAUDE.md; fi

# Claude Code 가드 훅 + 에이전트 — 가드는 --dangerously-skip-permissions 에서도 비밀값 열람과
# 되돌릴 수 없는 명령을 막는다. PreToolUse 항목과 permissions.deny 만 병합한다.
link claude/hooks/guard.py ~/.claude/hooks/guard.py
if command -v python3 >/dev/null; then
  python3 - "$HOME/.claude/settings.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
changed = False
# fail-open: guard.py 가 없으면(dotfiles 체크아웃을 옮겼을 때 등) exit 2 가 모든 도구를 막아 버린다.
want_entry = {"matcher": "Bash|Read|Edit|Write|MultiEdit|NotebookEdit|Grep",
              "hooks": [{"type": "command", "timeout": 10,
                         "command": '[ -f "$HOME/.claude/hooks/guard.py" ] && python3 "$HOME/.claude/hooks/guard.py"; exit 0'}]}
pre = d.setdefault("hooks", {}).setdefault("PreToolUse", [])
mine = [g for g in pre if any("guard.py" in h.get("command", "") for h in g.get("hooks", []))]
if mine != [want_entry]:
    pre[:] = [g for g in pre if g not in mine] + [want_entry]
    changed = True
deny = d.setdefault("permissions", {}).setdefault("deny", [])
# .env 규칙은 넣지 않는다: Read/Edit deny 는 cwd 기준이고 가드가 안내하는 안전한 대안
# (cut -d= -f1, grep -q)까지 막는다. .env 는 어디서든 guard.py 가 처리한다.
for r in [x for x in deny if x in ("Read(**/.env)", "Read(**/.env.local)", "Read(**/.env.production)", "Edit(**/.env)", "Write(**/.env)")]:
    deny.remove(r); changed = True
for r in ["Read(~/.claude/.credentials.json)", "Read(~/.ssh/id_*)", "Read(~/.zshenv.local)", "Read(~/.pgpass)"]:
    if r not in deny:
        deny.append(r); changed = True
if changed:
    with open(p, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False); f.write("\n")
    print("  → ~/.claude/settings.json 가드 훅 + permissions.deny 설정")
PY
fi

# Orca 에이전트 스킬(orca-cli, orchestration, computer-use)을 ~/.agents/skills 에 깔고 Claude Code 에 링크한다.
# CLI 는 리눅스에서 `orca-ide`(/usr/bin/orca 는 GNOME 화면 낭독기), macOS 에서 `orca`
# (Orca → Settings → General → Orca CLI 에서 등록). 다시 돌려도 안전: 그대로인 사본은 "No change" 로 나온다.
orca_cli=orca-ide; [ $os = darwin ] && orca_cli=orca
if [ -z "${INSTALL_SKIP_SERVICES:-}" ] && command -v $orca_cli >/dev/null; then
  $orca_cli skills install --skill orca-cli --skill orchestration --skill computer-use --agent claude 2>&1 \
    | sed "s/^/  ${D}orca 스킬${R} /"
fi

# ---- macOS ----
if [ $os = darwin ]; then
  link macos/karabiner.json          ~/.config/karabiner/karabiner.json
  link macos/vscode/settings.json    "$HOME/Library/Application Support/Code/User/settings.json"
  if [ $with_brew = 1 ] && command -v brew >/dev/null; then brew bundle --file "$repo/macos/Brewfile"; fi
fi

# ---- Linux: Google Drive 마운트 (사용자 서비스. gdrive 리모트가 생긴 뒤에만 켠다) ----
if [ $os = linux ] && [ -z "${INSTALL_SKIP_SERVICES:-}" ] && command -v systemctl >/dev/null; then
  link linux/systemd/rclone-gdrive.service ~/.config/systemd/user/rclone-gdrive.service
  systemctl --user daemon-reload
  if command -v rclone >/dev/null && rclone listremotes 2>/dev/null | grep -qx 'gdrive:'; then
    systemctl --user enable --now rclone-gdrive.service >/dev/null 2>&1 && echo "  ${G}→${R} rclone-gdrive.service (~/gdrive)"
  else
    echo "  ${Y}참고${R} gdrive 리모트가 아직 없다 — setup/MANUAL.md §3 을 한 뒤 install.sh 를 다시 실행"
  fi
fi

# ---- Linux 데스크톱 (WSL 은 윈도우 쪽 VS Code 를 쓴다) ----
if [ $os = linux ] && command -v code >/dev/null; then
  link macos/vscode/settings.json ~/.config/Code/User/settings.json
fi

# ---- 프로필 ----
# personal: 범용 위에 personal/(별도 비공개 레포) 의 값을 얹는다. vanilla: personal 을 가리키는 링크를 걷어낸다.
personal=${DOTFILES_PERSONAL:-$repo/personal}
if [ $profile = personal ] && [ ! -d "$personal" ]; then
  personal_repo=${DOTFILES_PERSONAL_REPO:-$(git -C "$repo" remote get-url origin 2>/dev/null | sed -E 's#(\.git)?$#-personal\1#')}
  echo "  ${C}clone${R} $personal_repo → ${personal/#$HOME/~}"
  git clone -q "$personal_repo" "$personal" \
    || { echo "personal 레포를 clone 못 했다 — DOTFILES_PERSONAL_REPO=<url> 로 다시 실행" >&2; exit 1; }
fi
personal_links=(
  "$personal/git/gitconfig:$HOME/.config/git/profile.gitconfig"
  "$personal/git/allowed-emails:$HOME/.config/git/allowed-emails"
  "$personal/git/blocked-domains:$HOME/.config/git/blocked-domains"
  "$personal/claude/CLAUDE.md:$HOME/.claude/CLAUDE.personal.md"
)
for f in "$personal"/claude/agents/*.md; do
  [ -e "$f" ] && personal_links+=("$f:$HOME/.claude/agents/$(basename "$f")")
done
for pair in "${personal_links[@]}"; do
  src=${pair%%:*} dst=${pair#*:}
  if [ $profile = personal ]; then
    link "$src" "$dst"
  fi
done
if [ $profile = vanilla ]; then
  # personal 링크, 그리고 프로필 도입 전 옛 위치(git/allowed-emails, claude/agents)를 가리키는 끊긴 링크
  for dst in ~/.config/git/profile.gitconfig ~/.config/git/allowed-emails ~/.config/git/blocked-domains \
             ~/.claude/CLAUDE.personal.md ~/.claude/agents/*.md; do
    [ -L "$dst" ] || continue
    t=$(readlink "$dst")
    if [[ $t == "$personal/"* || $t == "$repo/personal/"* ]] || { [[ $t == "$repo/"* ]] && [ ! -e "$dst" ]; }; then
      rm "$dst"; echo "  ${Y}제거${R} ${dst/#$HOME/~} (personal)"
    fi
  done
fi
if [ $profile = vanilla ] && [ -z "$(git config --global --includes user.email 2>/dev/null)" ]; then
  if [ -t 0 ]; then
    read -r -p "git 이름: " gname; read -r -p "git 메일: " gmail
    git config --file ~/.gitconfig.local user.name "$gname"
    git config --file ~/.gitconfig.local user.email "$gmail"
    echo "  ${G}→${R} ~/.gitconfig.local user.name/email"
  else
    echo "  ${Y}참고${R} git 신원이 없다 — git config --file ~/.gitconfig.local user.email <메일> (이름도)"
  fi
fi

# ---- 점검 ----
echo
[ -d ~/.oh-my-zsh ] || echo "  ${Y}참고${R} Oh My Zsh 가 없다 — setup/ubuntu.sh(Linux)를 돌리거나 직접 설치"
[ -d ~/.oh-my-zsh/custom/themes/powerlevel10k ] || echo "  ${Y}참고${R} powerlevel10k 테마가 없다"
command -v jq >/dev/null || echo "  ${Y}참고${R} 상태 줄에 jq 가 필요하다"
for f in ~/.zshrc.bak ~/.gitconfig.bak; do
  [ -e "$f" ] && echo "  ${Y}참고${R} ${f/#$HOME/~} 를 확인 — 머신별·비밀 설정은 ${f%.bak}.local 로 옮길 것"
done
echo "  ${G}완료${R} — 새 셸을 연다 (exec zsh)"
