export ZSH="$HOME/.oh-my-zsh"
export ZSH_THEME="gallifrey"
export VI_MODE_SET_CURSOR=true
plugins=(
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

if [[ -z "$TMUX" && -z "$SSH_CONNECTION" ]]; then
  if ! tmux attach &> /dev/null; then
      tmux
  fi
fi

# HACK: direnv does not support recursive loading of configs
# https://github.com/direnv/direnv/issues/606
if [ -f ~/.envrc ]; then
  source ~/.envrc
fi

function pet-run() {
  pet search | bash -xe
}
