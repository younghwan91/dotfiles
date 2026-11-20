#!/bin/bash
# macOS 초기 설정: Homebrew, Xcode CLT, gh, Oh My Zsh + Powerlevel10k + 플러그인, uv,
# 그다음 dotfiles (install.sh --brew 가 macos/Brewfile 을 전부 설치한다).
#
# 새 Mac 에서 실행한다. 다시 돌려도 안전 — 이미 있는 단계는 건너뛴다.
#   bash setup.sh
set -e

echo "===================================================="
echo "   macOS 환경 설정"
echo "===================================================="
read -p "설정을 시작할까요? (y/n): " confirm
[[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || { echo "설정을 취소했습니다."; exit 0; }

# 1. Xcode Command Line Tools (git, make, clang)
if ! xcode-select -p >/dev/null 2>&1; then
    echo "🛠  Xcode Command Line Tools 설치 중 — 창에서 설치를 마친 뒤 이 스크립트를 다시 실행하세요."
    xcode-select --install
    exit 0
fi

# 2. Homebrew
if ! command -v brew >/dev/null; then
    echo "🍺 Homebrew 설치 중..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)" && break; done

# 3. 비공개 dotfiles 레포를 받는 데 필요한 최소한
brew install gh git jq
gh auth status >/dev/null 2>&1 || gh auth login

# 4. uv 로 Python 설치
if ! command -v uv >/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
uv python install 3.10 3.11 3.12

# graphify (코드 지식 그래프. 전역 CLAUDE.md 가 쓴다). 스킬은 ~/.claude/skills 에 깔린다.
uv tool install graphifyy

# 5. Oh My Zsh 및 Powerlevel10k (글리프는 Mac 터미널이 그리므로 폰트도 여기서 설치)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
clone() { [ -d "$2" ] || git clone --depth=1 "$1" "$2"; }
clone https://github.com/romkatv/powerlevel10k.git              "$ZSH_CUSTOM/themes/powerlevel10k"
clone https://github.com/zsh-users/zsh-autosuggestions.git      "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone https://github.com/zsh-users/zsh-syntax-highlighting.git  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
brew install --cask font-meslo-lg-nerd-font || true

# 6. Dotfiles — 설정을 링크하고 macos/Brewfile 로 `brew bundle` 실행
if [ ! -d "$HOME/git/dotfiles" ]; then
    mkdir -p "$HOME/git"
    # 다른 레포면 DOTFILES_REPO=<owner>/<repo>
    gh repo clone "${DOTFILES_REPO:-$(gh api user -q .login)/dotfiles}" "$HOME/git/dotfiles"
fi
"$HOME/git/dotfiles/install.sh" ${DOTFILES_PROFILE:+--profile "$DOTFILES_PROFILE"} --brew
graphify install --platform claude

# 7. 최신 macOS 는 zsh 가 이미 기본 셸이다. 그래도 확인
[ "$SHELL" = "$(command -v zsh)" ] || [ "$SHELL" = /bin/zsh ] || chsh -s /bin/zsh

echo "----------------------------------------------------"
echo "✅ 설정 완료."
echo "남은 수동 단계:"
echo "  1. iTerm2 → Settings → General → Settings: ~/git/dotfiles/personal/macos/iterm2.plist 에서 불러오기 (personal 프로필)"
echo "  2. 터미널 폰트를 'MesloLGS Nerd Font' 로 설정"
echo "  3. VS Code 확장: xargs -n1 code --install-extension < ~/git/dotfiles/macos/vscode/extensions.txt"
echo "그다음: exec zsh"
