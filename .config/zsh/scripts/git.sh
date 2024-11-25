#autoload
#!/bin/bash

# git aliases because my fingers are getting arthritis

alias gp="git pull --rebase"
alias gs="git status"

if which gl > /dev/null; then
  unalias gl # AHHHHHHHHHHHHHHHHHHHH
fi
function gl() {
  numLogs=8
  if [[ ! -z "$@" ]]; then
    numLogs="$@"
  fi

  git log -n "${numLogs}"
}

if which gr > /dev/null; then
  unalias gr # AHHHHHHHHHHHHHHHHHHHH
fi
function gr() {
  expectedRemoteName="upstream"

  # if number of remotes is 1, assume I know what Im doing...? :/
  numRemotes=$(git remote -v | awk '{print $1}' | uniq | wc -l | tr -d '[:blank:]')
  if (( $numRemotes == 1 )); then
    expectedRemoteName=$(git remote | tr -d '[:blank:]')
  fi

  remoteMainBranch=$(git remote show $expectedRemoteName | grep 'HEAD branch' | cut -d: -f2 | tr -d '[:blank:]')

  if (( $numRemotes == 1 )); then
    remoteUrl=$(git remote -v | grep "$expectedRemoteName" | grep fetch | awk '{print $2}')
    echo "[WARN] Rebasing against '$remoteMainBranch' in $remoteUrl"
  fi
  git rebase "${expectedRemoteName}/${remoteMainBranch}" -i
}

if which gf > /dev/null; then
  unalias gf # AHHHHHHHHHHHHHHHHHHHH
fi
function gf() { git commit --fixup "$@" }

# force push current branch, but only if we're pushing to our own fork
function gpoh() {
  pushRemote="$(git remote -v | grep origin | grep push | awk '{print $2}')"

  if ! echo "$pushRemote" | grep $USER &> /dev/null; then
    echo "[FATAL] 'origin' $pushRemote does NOT look like your fork!"
    return 1
  fi

  git push origin +HEAD
}
