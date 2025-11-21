export ZSH="$HOME/.oh-my-zsh"
export ZSH_THEME="gallifrey"
export VI_MODE_SET_CURSOR=true
plugins=(
  zsh-autosuggestions
  zsh-syntax-highlighting
  fast-syntax-highlighting
  zsh-autocomplete
  direnv
  docker
  fzf
  git
  kubectl
  vi-mode
)
source $ZSH/oh-my-zsh.sh

export PATH="$HOME/.local/bin:$PATH:/snap/bin"
if which go &> /dev/null; then
  export PATH="$PATH:$(go env GOPATH)/bin"
fi

autoload -Uz compinit && compinit

# TODO: figure out why autoload didn't work here even w/ fpath
for script in $(ls ~/.config/zsh/scripts); do
  source ~/.config/zsh/scripts/$script
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
