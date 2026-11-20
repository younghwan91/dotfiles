#!/bin/bash

# 데이터 사이언티스트 / ML 엔지니어용 Ubuntu 설치 스크립트
# 내용: SSH, uv, Zsh, 필수 유틸리티
# 변경:
#  - 2026-09-13: dotfiles 로 옮김. 셸·git 설정은 ~/.zshrc 에 덧붙이지 않고
#    install.sh 가 맡는다
#  - 2026-10-27: 데스크톱은 MesloLGS NF + GNOME Terminal 글꼴, 한글 입력(한/영 키),
#    Orca, Chrome, VS Code 를 받는다(09-10 의 글꼴 제거는 SSH 전용 서버를 가정했다).
#    Jetson 은 JetPack + jtop. 모든 호스트에 rclone(+ ~/gdrive 마운트), Node(nvm), docker 그룹, git-lfs, bat, lsd, vim 플러그인, 전역 CLAUDE.md
#  - 2026-11-02: apt 를 대화창 없이(sudo_apt), chsh 는 sudo 로, 끝에 재부팅 안내
# 2026-09-10 Claude Code 수정:
#  - RSA 키 생성 생략 (이 호스트엔 ed25519 키가 이미 있다)
#  - 서버 쪽 MesloLGS NF 글꼴 설치 제거 (SSH 너머로는 효과가 없다.
#    Powerlevel10k 글리프는 서버가 아니라 클라이언트 터미널이 그린다)
#  - .zshrc 덧붙이기 가드가 "uv" 부분 문자열(파일 다른 곳에 이미 있다) 대신
#    고유 표식을 확인한다

set -e

echo "===================================================="
echo "   Ubuntu 서버 환경 전체 설치"
echo "===================================================="

# 1. 시작 확인
read -p "설치를 시작할까요? (y/n): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "설치를 취소했습니다."
    exit 0
fi

# 개인 PC 전용: 비밀번호 없는 sudo (되돌리기: sudo rm /etc/sudoers.d/90-$USER-nopasswd)
read -p "$USER 에게 비밀번호 없는 sudo 를 줄까요? (y/n): " nopasswd
if [[ $nopasswd == [yY] ]]; then
    echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-$USER-nopasswd" > /dev/null
    sudo chmod 440 "/etc/sudoers.d/90-$USER-nopasswd"
    sudo visudo -c > /dev/null
fi

# 대화창 없는 apt: sudo 는 환경의 DEBIAN_FRONTEND 를 버리므로 명령 안에 넘긴다. 없으면 tty 없이
# 돌 때 needrestart 의 "Pending kernel upgrade" 창이 "Failed to open terminal" 로 실패한다.
sudo_apt() { sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "$@"; }

# 2. 필수 도구
echo "----------------------------------------------------"
echo "📦 시스템 패키지 설치 중..."
sudo_apt update && sudo_apt upgrade -y
sudo_apt install -y build-essential curl git wget software-properties-common \
    libssl-dev zsh dos2unix openssh-server ufw \
    htop tmux ncdu jq tldr tree rsync vim git-lfs bat lsd fuse3

# GitHub CLI
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo_apt update && sudo_apt install gh -y
fi

# rclone (Google Drive). 리모트 설정에 OAuth 토큰이 들어 있어 이 레포엔 두지 않는다:
# PC 마다 한 번 `rclone config create gdrive drive scope=drive` 를 실행한다.
if ! command -v rclone &> /dev/null; then
    curl -fsSL https://rclone.org/install.sh | sudo bash
fi
grep -q '^user_allow_other' /etc/fuse.conf || echo user_allow_other | sudo tee -a /etc/fuse.conf > /dev/null

# 3. SSH 서버와 키
echo "----------------------------------------------------"
echo "🔑 SSH 설정 중..."
sudo systemctl enable ssh --now
sudo ufw allow ssh || true

if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_rsa" ]; then
    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -N "" -f "$HOME/.ssh/id_ed25519"
else
    echo "SSH 키가 이미 있어 생성을 건너뜁니다."
fi

# 4. 데스크톱 전용: GNOME Terminal 용 MesloLGS NF + 한글 입력 (ibus-hangul)
# SSH 로는 클라이언트 터미널이 p10k 글리프를 그리므로 화면 없는 서버는 건너뛴다.
echo "----------------------------------------------------"
if command -v gnome-terminal &> /dev/null; then
    echo "🎨 데스크톱 감지: MesloLGS NF 와 한글 입력 설치 중..."
    FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"
    for s in Regular Bold Italic "Bold Italic"; do
        curl -fsSL -o "$FONT_DIR/MesloLGS NF $s.ttf" \
            "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20${s// /%20}.ttf"
    done
    fc-cache -f "$FONT_DIR"
    profile=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
    schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$profile/"
    gsettings set "$schema" use-system-font false
    gsettings set "$schema" font 'MesloLGS NF 12'

    sudo_apt install -y ibus-hangul fonts-noto-cjk
    # 입력 소스는 Hangul 하나만: 영문으로 시작하고 한/영 키로 전환한다. 'us' 와 같이 두면
    # Super+Space 로 Hangul 을 고르기 전까지 한/영 키가 아무 일도 안 했다. 한/영 키는
    # korean:ralt_hangul 로 매핑하지 않으면 오른쪽 Alt 를 보낸다.
    gsettings set org.gnome.desktop.input-sources sources "[('ibus', 'hangul')]"
    gsettings set org.gnome.desktop.input-sources xkb-options "['korean:ralt_hangul', 'korean:rctrl_hanja']"

    # 유휴 상태에서 화면 끄기·어둡게·절전을 모두 끈다 (Ubuntu 기본: 5분에 화면 끔, 전원 연결 시 절전).
    power=org.gnome.settings-daemon.plugins.power
    gsettings set org.gnome.desktop.session idle-delay 0
    gsettings set $power idle-dim false
    gsettings set $power sleep-inactive-ac-type 'nothing'
    gsettings set $power sleep-inactive-battery-type 'nothing'

    # Orca (병렬 에이전트 IDE) — macOS Brewfile 과 같은 배포처. 실행: `orca-ide`
    # (/usr/bin/orca 는 GNOME 화면 낭독기라 이것과 다르다).
    if ! dpkg -s orca-ide &> /dev/null; then
        gh auth status > /dev/null 2>&1 || gh auth login
        orca_dir=$(mktemp -d)
        gh release download -R stablyai/orca -p "orca-ide_*_$(dpkg --print-architecture).deb" -D "$orca_dir"
        sudo_apt install -y "$orca_dir"/orca-ide_*.deb
        rm -rf "$orca_dir"
    fi

    # Firefox — Ubuntu 데스크톱은 snap 으로 기본 포함. 없을 때만 깐다(무료 VPN 내장).
    command -v firefox &> /dev/null || sudo snap install firefox

    # Google Chrome (amd64·arm64 빌드). .deb 가 업데이트용 Google apt 저장소를 추가한다.
    if ! command -v google-chrome &> /dev/null; then
        chrome_deb=$(mktemp --suffix=.deb)
        curl -fsSL -o "$chrome_deb" "https://dl.google.com/linux/direct/google-chrome-stable_current_$(dpkg --print-architecture).deb"
        sudo_apt install -y "$chrome_deb"
        rm -f "$chrome_deb"
    fi

    # VS Code. debconf 응답으로 .deb 가 업데이트용 Microsoft apt 저장소를 추가한다.
    # Fira Code 는 macos/vscode/settings.json 의 편집기 글꼴이다.
    if ! command -v code &> /dev/null; then
        code_deb=$(mktemp --suffix=.deb)
        curl -fsSL -o "$code_deb" "https://update.code.visualstudio.com/latest/linux-deb-$(dpkg --print-architecture)/stable"
        echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections
        sudo_apt install -y "$code_deb"
        rm -f "$code_deb"
    fi
    sudo_apt install -y fonts-firacode
else
    echo "ℹ️  데스크톱 없음: 글꼴과 한글 입력을 건너뜁니다 (클라이언트에 'MesloLGS NF' 를 설치하세요)."
fi

# 4b. NVIDIA Jetson 전용 (L4T 가 /etc/nv_tegra_release 를 만든다): JetPack SDK (CUDA, cuDNN,
# TensorRT; 수 GB) 와 jtop. dGPU 장비는 아직 여기서 다루지 않는다.
if [ -f /etc/nv_tegra_release ]; then
    echo "----------------------------------------------------"
    echo "🟢 Jetson 감지: JetPack 과 jtop 설치 중..."
    sudo_apt install -y nvidia-jetpack python3-pip
    # jtop 은 root systemd 서비스가 필요해 시스템 파이썬에 설치한다. pip 휠은 더 이상 그 서비스를
    # 스스로 등록하지 않아서 --install-service 를 따로 돌린다.
    sudo pip3 install --break-system-packages -U jetson-stats
    sudo jtop --install-service
fi

# sudo 없이 docker (다음 로그인부터 적용)
if getent group docker > /dev/null; then
    sudo usermod -aG docker "$USER"
fi

# 5. 파이썬 관리 (uv)
echo "----------------------------------------------------"
echo "🐍 'uv' 로 파이썬 설정 중..."
if ! command -v uv &> /dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
uv python install 3.10 3.11 3.12

# graphify(코드 지식 그래프) — 전역 CLAUDE.md 가 쓴다. 스킬은 install.sh 뒤에 ~/.claude/skills 로 들어간다.
uv tool install graphifyy

# nvm 으로 Node LTS. PROFILE=/dev/null: zsh/zshrc 가 이미 nvm 을 불러오고 ~/.zshrc 는 레포 심볼릭 링크다.
echo "----------------------------------------------------"
echo "🟩 nvm 으로 Node 설정 중..."
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    nvm_tag=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -r .tag_name)
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$nvm_tag/install.sh" | PROFILE=/dev/null bash
fi
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'

# 6. Oh My Zsh 와 Powerlevel10k
echo "----------------------------------------------------"
echo "🐚 Zsh 와 Powerlevel10k 설정 중..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
rm -rf "$ZSH_CUSTOM/themes/powerlevel10k" "$ZSH_CUSTOM/plugins/zsh-autosuggestions" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# 7. Dotfiles (zshrc, p10k, gitconfig, vimrc, 명령들, Claude 상태줄)
if [ ! -d "$HOME/git/dotfiles" ]; then
    gh auth status >/dev/null 2>&1 || gh auth login
    # 다른 레포면 DOTFILES_REPO=<owner>/<repo>
    gh repo clone "${DOTFILES_REPO:-$(gh api user -q .login)/dotfiles}" "$HOME/git/dotfiles"
fi
"$HOME/git/dotfiles/install.sh" ${DOTFILES_PROFILE:+--profile "$DOTFILES_PROFILE"} --claude-md
graphify install --platform claude
# sudo: 그냥 chsh 는 비밀번호를 묻고 터미널이 없으면 실패한다.
sudo chsh -s "$(command -v zsh)" "$USER" || true

# Vim 플러그인: vimrc 의 첫 실행 설치는 터미널이 없으면 안 돌아서 pty 안에서 돌린다.
[ -d "$HOME/.vim/bundle/Vundle.vim" ] || git clone -q https://github.com/VundleVim/Vundle.vim.git "$HOME/.vim/bundle/Vundle.vim"
script -qc "vim +PluginInstall +qall" /dev/null > /dev/null || true

# VS Code 확장 (설정은 install.sh 가 링크한다). Windows/WSL 전용 확장은 건너뛴다.
if command -v code &> /dev/null; then
    # `code` 한 번에 전부 설치: 확장마다 `code` 를 따로 부르면 하나도 설치되지 않았다.
    mapfile -t exts < <(grep -vE '^(ms-vscode-remote\.remote-wsl|ms-vscode\.powershell|blake-mealey\.generate-wt-scheme)$' \
        "$HOME/git/dotfiles/macos/vscode/extensions.txt")
    code "${exts[@]/#/--install-extension=}" > /dev/null || true
fi

echo "----------------------------------------------------"
echo "✅ 설치 완료."
echo "📋 GitHub 용 공개 키:"
cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || cat "$HOME/.ssh/id_rsa.pub"
echo "----------------------------------------------------"
[ -f /var/run/reboot-required ] && echo "🔁 재부팅 필요 (새 커널 또는 핵심 라이브러리): sudo reboot"
echo "다음: ~/git/dotfiles/setup/MANUAL.md 의 로그인들, 그다음 exec zsh"
