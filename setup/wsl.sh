#!/bin/bash

# 에러가 나면 바로 종료
set -e

echo "===================================================="
echo "   WSL Ubuntu AI/로보틱스 환경 설정"
echo "===================================================="

# 1. 시작 확인
read -r -p "설정을 시작할까요? (y/n): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "사용자가 설정을 취소했습니다."
    exit 0
fi

# 2. 바탕화면 경로 찾기 (레지스트리 기준)
echo "🔍 윈도우 바탕화면 경로를 찾는 중..."
# 추측하지 않도록 레지스트리를 직접 조회한다
RAW_PATH=$(powershell.exe -Command "(Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name 'Desktop').Desktop" | tr -d '\r')

# 윈도우 경로(C:\Users\...)를 WSL 경로(/mnt/c/Users/...)로 변환
ACTIVE_DESKTOP=$(wslpath "$RAW_PATH")

echo "📍 바탕화면 경로: $ACTIVE_DESKTOP"
FONT_DIR="$ACTIVE_DESKTOP/MesloLGS_NF"

# 3. 시스템 업데이트 및 필수 도구
echo "----------------------------------------------------"
echo "📦 시스템 패키지 설치 중..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential curl git wget software-properties-common \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    ffmpeg libsm6 libxext6 python3-tk zsh dos2unix

# 4. Python 관리 (uv)
echo "🐍 'uv' 로 Python 설정 중..."
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv python install 3.10 3.11 3.12

# graphify (코드 지식 그래프. 전역 CLAUDE.md 가 쓴다). 스킬은 ~/.claude/skills 에 깔린다.
uv tool install graphifyy

# 5. Oh My Zsh 및 Powerlevel10k 설정
echo "🐚 Zsh 와 Powerlevel10k 설정 중..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
rm -rf "$ZSH_CUSTOM/themes/powerlevel10k" "$ZSH_CUSTOM/plugins/zsh-autosuggestions" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"


# 6. 확인한 경로로 폰트 내려받기
echo "🎨 MesloLGS NF 폰트를 바탕화면에 내려받는 중..."
mkdir -p "$FONT_DIR"

URLS=(
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
)

for url in "${URLS[@]}"; do
    filename=$(basename "$url" | sed 's/%20/ /g')
    wget -q -O "$FONT_DIR/$filename" "$url"
done

# 7. Dotfiles (zshrc + WSL 레이어, gitconfig, vimrc, 명령)
sudo apt install -y gh
if [ ! -d "$HOME/git/dotfiles" ]; then
    gh auth status >/dev/null 2>&1 || gh auth login
    # 다른 레포면 DOTFILES_REPO=<owner>/<repo>
    gh repo clone "${DOTFILES_REPO:-$(gh api user -q .login)/dotfiles}" "$HOME/git/dotfiles"
fi
"$HOME/git/dotfiles/install.sh" ${DOTFILES_PROFILE:+--profile "$DOTFILES_PROFILE"}
graphify install --platform claude
chsh -s "$(command -v zsh)" || true

echo "----------------------------------------------------"
echo "✅ 설정 완료."
echo "1. 'zsh' 를 입력해 셸에 들어갑니다."
echo "2. 바탕화면 폴더의 폰트를 설치합니다: $FONT_DIR"
echo "3. VS Code 터미널 폰트를 'MesloLGS NF' 로 바꿉니다."
