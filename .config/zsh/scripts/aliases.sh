#autoload

alias dc="docker compose"
alias vim="nvim"
alias t="talosctl"

if uname | grep Linux &> /dev/null; then
  batbin="batcat"
else
  batbin="bat"
fi
if which $batbin &> /dev/null; then
  alias cat="$batbin -pP"
fi
