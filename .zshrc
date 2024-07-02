export ZSH="$HOME/.oh-my-zsh"
export ZSH_THEME="gallifrey"
export VI_MODE_SET_CURSOR=true
plugins=(
  ag
  direnv
  fzf
  git
  kubectl
  talosctl
  vi-mode
)
source $ZSH/oh-my-zsh.sh

export PATH="$HOME/.local/bin:$PATH:/snap/bin"

autoload -Uz compinit && compinit

# TODO: figure out why autoload didn't work here even w/ fpath
for script in $(ls ~/.config/zsh/scripts); do
  source ~/.config/zsh/scripts/$script
done

if [ "$TMUX" = "" ]; then
  if ! tmux ls &> /dev/null; then
    tmux
  else
    tmux attach-session
  fi
fi
