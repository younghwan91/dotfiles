# macOS

# Homebrew (Apple Silicon 먼저, 없으면 Intel)
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [[ -x $b ]] && { eval "$($b shellenv)"; break; }
done

command -v bat >/dev/null && alias cat='bat'

# Homebrew cask 로 깐 Miniconda 가 있으면
_conda=/opt/homebrew/Caskroom/miniconda/base
if [[ -x $_conda/bin/conda ]]; then
  if __conda_setup="$("$_conda/bin/conda" shell.zsh hook 2>/dev/null)"; then
    eval "$__conda_setup"
  elif [[ -f $_conda/etc/profile.d/conda.sh ]]; then
    source "$_conda/etc/profile.d/conda.sh"
  fi
  unset __conda_setup
fi
unset _conda

# iTerm 에서만, 하루 최대 한 번 백그라운드로 brew update + upgrade.
if [[ $TERM_PROGRAM == iTerm.app ]] && command -v brew >/dev/null; then
  () {
    local stamp="$HOME/.brew_last_update"
    if [[ ! -f $stamp ]] || [[ -n $(find "$stamp" -mtime +0 2>/dev/null) ]]; then
      touch "$stamp"
      (brew update && brew upgrade --greedy) &>/tmp/brew-update.log &!
    fi
  }
fi
