# Linux (실머신 / VM). wsl.zsh 도 이 파일을 불러온다.

# Debian/Ubuntu 는 bat 을 `batcat` 이름으로 배포한다.
if command -v batcat >/dev/null; then alias cat='batcat'
elif command -v bat >/dev/null; then alias cat='bat'
fi

command -v nvidia-smi >/dev/null && alias gpustat='watch -n 1 nvidia-smi'

# CUDA 툴킷(Jetson 의 JetPack 이나 dGPU 용 CUDA)은 기본으로 PATH 에 없다.
if [[ -d /usr/local/cuda/bin ]]; then
  export PATH="/usr/local/cuda/bin:$PATH"
  export LD_LIBRARY_PATH="/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# `update` = 생각날 때 한 번 돌리면 이 기기를 최신으로 맞춘다. 단계마다 "==> [n/N]" 을 찍는다.
#   apt update → full-upgrade → autoremove → snap → uv tools → npm global
#   → 펌웨어 목록(설치 안 함, WSL 제외) → 재부팅 필요 알림
# 없는 도구는 단계에서 빠진다. 한 단계가 실패해도 나머지는 돌고, 끝에 실패 목록을 보여준다.
# `update install foo` = apt install foo.
# 그냥 sudo 를 쓴다. 비밀번호 입력을 건너뛰려면 셸 파일에 비밀번호를 두지 말고
# apt 용 sudoers 규칙을 추가한다.
if ! typeset -f update >/dev/null; then
  update() {
    if (( $# )); then sudo apt "$@"; return; fi

    # "제목|명령" — 명령은 여기 적힌 상수만 eval 한다
    local -a steps=(
      "apt update|sudo apt update"
      "apt full-upgrade|sudo apt full-upgrade -y"
      "apt autoremove|sudo apt autoremove -y"
    )
    command -v snap >/dev/null && [[ -S /run/snapd.socket ]] && steps+=("snap refresh|sudo snap refresh")
    command -v uv >/dev/null && steps+=("uv tools upgrade|uv tool upgrade --all")
    command -v npm >/dev/null && steps+=("npm global update|npm update -g")
    # 펌웨어는 하드웨어를 건드리니 목록만. 설치는 손으로 `fwupdmgr update`. rc 2 = 업데이트 없음.
    if command -v fwupdmgr >/dev/null && [[ -z $WSL_DISTRO_NAME ]]; then
      steps+=("firmware check (list only)|fwupdmgr get-updates -y --no-unreported-check </dev/null; (( \$? == 0 || \$? == 2 ))")
    fi

    local -a failed=()
    local i=0 n=${#steps} label
    for s in $steps; do
      (( i++ )); label=${s%%|*}
      print -P "\n%F{blue}==>%f %B[$i/$n] $label%b"
      eval "${s#*|}" || failed+=("$label")
    done

    print
    [[ -f /var/run/reboot-required ]] && print -P "%F{yellow}==> 재부팅 필요%f ($(tr '\n' ' ' </var/run/reboot-required.pkgs 2>/dev/null | cut -c1-80))"
    if (( ${#failed} )); then
      print -P "%F{red}==> 실패한 단계:%f ${(j:, :)failed}"
      return 1
    fi
    print -P "%F{green}==> update done%f"
  }
fi
