export ZSH="$HOME/.oh-my-zsh"
export ZSH_THEME="gallifrey"
export VI_MODE_SET_CURSOR=true

DISABLE_AUTO_UPDATE=true

plugins=(
  zsh-autosuggestions
  fast-syntax-highlighting
  # this one is too spastic for me...for now
  # zsh-autocomplete
  direnv
  # or podman?
  # docker
  # autocomplete script takes care of most of my needs for now
  # fzf
  git
  # eh...
  # kubectl
  vi-mode
)
source $ZSH/oh-my-zsh.sh

setopt noincappendhistory
setopt nosharehistory

export PATH="$HOME/.local/bin:$PATH:/snap/bin"
if which go &> /dev/null; then
  export PATH="$PATH:$(go env GOPATH)/bin"
fi

# TODO: figure out why autoload didn't work here even w/ fpath
for script in ~/.config/zsh/scripts/*; do
  source $script
done

# HACK: direnv does not support recursive loading of configs
# https://github.com/direnv/direnv/issues/606
# pipe to dev null to avoid output for second time
[ -f ~/.envrc ] && source ~/.envrc > /dev/null

if [[ -z "$TMUX" && "$AUTO_TMUX" = "true" ]]; then
  export TMUX_INIT=true

  # not an SSH conn; guessing from local
  if ! env | grep SSH_CONNECTION &> /dev/null; then
    if ! tmux attach &> /dev/null; then
        tmux && exit 0
    fi
  fi

  # over SSH connection
  sshHost=$(env | grep SSH_CONNECTION | cut -d= -f2 | awk '{ print $1 }')
  tmux new-session -A -s "from-${sshHost}" && exit 0
fi
