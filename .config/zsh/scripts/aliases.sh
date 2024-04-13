#autoload

alias dc="docker compose"
alias vim="nvim"

if uname | grep Linux &> /dev/null; then
  alias cat="batcat"
else
  alias cat="bat"
fi
