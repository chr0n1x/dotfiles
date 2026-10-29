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
  # autocomplete script takes care of most of my needs for now
  # fzf
  git
  kubectl
  vi-mode
)
source $ZSH/oh-my-zsh.sh

setopt noincappendhistory
setopt nosharehistory

export PATH="$HOME/.local/bin:$PATH:/snap/bin"
if which go &> /dev/null; then
  export PATH="$PATH:$(go env GOPATH)/bin"
fi

# podman fallback on Linux/Windows where docker isn't available
if ! command -v docker &> /dev/null && command -v podman &> /dev/null; then
  alias docker=podman
fi

# HACK: direnv does not support recursive loading of configs
# https://github.com/direnv/direnv/issues/606
# pipe to dev null to avoid output for second time
# sourced before the script loop so scripts can depend on its exports
[ -f ~/.envrc ] && source ~/.envrc > /dev/null

# TODO: figure out why autoload didn't work here even w/ fpath
for script in ~/.config/zsh/scripts/*; do
  source $script
done

if [[ -z "$TMUX" && "$AUTO_TMUX" = "true" ]]; then
  export TMUX_INIT=true

  # not an SSH conn; guessing from local
  if ! env | grep SSH_CONNECTION &> /dev/null; then
    if ! tmux attach &> /dev/null; then
        tmux && exit 0
    fi
  fi

  # over SSH connection. Name the session after the client's hostname when
  # rDNS resolves it (getent, ~6ms), falling back to the client IP.
  client_ip=$(env | grep SSH_CONNECTION | cut -d= -f2 | awk '{ print $1 }')
  host_name=$(getent hosts "$client_ip" 2>/dev/null | awk '{print $2}' | cut -d. -f1)
  [ -n "$host_name" ] || host_name="$client_ip"
  tmux new-session -A -s "from-${host_name}" && exit 0
fi

alias drift="drift --scene rain --fps 120 --theme rosepine"

# Pi
export PATH="/home/kran/.local/share/pi-node/node-v22.23.2-linux-arm64/bin:$PATH"
