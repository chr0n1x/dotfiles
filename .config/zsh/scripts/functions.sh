function dex {
  if docker version &> /dev/null; then
    docker run -v $(pwd):/root/workspace --workdir /root/workspace --rm -ti "$@"
  else
    echo "Docker isn't installed or has not been started."
  fi
}

function dvim {
    dex --entrypoint "nvim" chr0n1x/dev-env
}

function k8s-shell {
    kubectl run "$@-test-shell" --rm -i --tty --image ubuntu -- /bin/bash
    kubectl delete pod "$@-test-shell"
}

function fzmux {
    fileList=""

    # lol there has to be a better way, im just dumb
    for pane in $(tmux list-panes -s | cut -d: -f1);
    do
      cachefile=/tmp/tmux-fzf-${pane}-txt
      fileList="$fileList $cachefile"
      # max scrollback should probably be fetched from tmux config
      tmux capture-pane -pS -10000 -t $pane > $cachefile
    done

    matchingPanes=$( \
      grep -R \
      "$(find /tmp/tmux-fzf-*-txt -type f -exec cat {} \; | fzf)" \
      /tmp/tmux-fzf-*-txt \
      | cut -d: -f1 | sort | uniq \
    )
    rm /tmp/tmux-fzf-*-txt

    # not sure what is happening in this case
    if [ -z "$matchingPanes" ]; then
      echo "Could not find pane to swap to"
      exit 0
    fi

    echo "Found matches in: "
    for file in $matchingPanes; do
      echo $file | cut -d- -f3
    done
    if [ "$(echo $matchingPanes | wc -l)" != 1 ]; then
      echo "multiple or no matches in panes:"
      for file in $matchingPanes; do
        echo $file | cut -d- -f3
      done
      exit 1
    fi
    if [ "$(echo $matchingPanes | wc -l)" != 1 ]; then
      echo "multiple or no matches in panes:"
      for file in $matchingPanes; do
        echo $file | cut -d- -f3
      done
      exit 1
    fi

    paneName=$(echo $matchingPanes | cut -d- -f3)
    paneID=$(tmux list-panes -s | grep "$paneName\:" | awk '{ print $7 }')
    cmd="tmux select-window -t $(echo $paneName | cut -d. -f1) && tmux select-pane -t $(echo $paneName | cut -d. -f2)"
    echo $cmd
    eval $cmd
}
