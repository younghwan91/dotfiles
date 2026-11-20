# WSL — Linux 에 윈도우 연동을 더한다.
source "${0:A:h}/linux.zsh"

alias open='explorer.exe'                       # open . → 윈도우 탐색기
alias pbcopy='clip.exe'
alias pbpaste='powershell.exe -NoProfile -Command Get-Clipboard | tr -d "\r"'

# 윈도우 사용자 프로필을 $WINHOME 으로 (예: /mnt/c/Users/<you>)
if command -v wslpath >/dev/null && [[ -z $WINHOME ]]; then
  WINHOME=$(wslpath "$(cmd.exe /C 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')" 2>/dev/null)
  export WINHOME
fi
