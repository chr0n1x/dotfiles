function tmux-list-all {
  tmux list-panes -F '#{session_name}:#{window_index}.#{pane_index}-#{history_size}'
}

function fzmux {
    for pane in $(tmux-list-all);
    do
      # has to be a better way, im just dumb
      paneID=$(echo $pane | cut -d- -f1)
      historySize=$(echo $pane | cut -d- -f2)
      cachefile="/tmp/tmux-fzf-${paneID}-txt"
      # only fetch what's _currently_ in the buffer, not the max
      tmux capture-pane -pS -$historySize -t $paneID > $cachefile
    done

    fzcmd='grep -R "$(cat /tmp/tmux-fzf-*-txt | fzf)" /tmp/tmux-fzf-*-txt | grep -oP "/tmp/tmux-fzf-\K.*-txt" | cut -d- -f1 | sort | uniq'
    tmux display-popup "$fzcmd | xargs -I {} echo 'tmux select-pane -t {}'"
    rm /tmp/tmux-fzf-*-txt

    # TODO: capture command from above
}
