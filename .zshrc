export ZSH="$HOME/.oh-my-zsh"
export ZSH_THEME="gallifrey"
export VI_MODE_SET_CURSOR=true
plugins=(
  direnv
  docker
  fzf
  git
  kubectl
  # talosctl
  vi-mode
)
source $ZSH/oh-my-zsh.sh

export PATH="$HOME/.local/bin:$PATH:/snap/bin"

autoload -Uz compinit && compinit

# TODO: figure out why autoload didn't work here even w/ fpath
for script in $(ls ~/.config/zsh/scripts); do
  source ~/.config/zsh/scripts/$script
done

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
