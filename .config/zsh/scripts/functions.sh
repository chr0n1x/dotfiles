function dex {
  if docker version &> /dev/null; then
    docker run -v $(pwd):/root/workspace --workdir /root/workspace --rm -ti "$@"
  else
    echo "Docker isn't installed or has not been started."
  fi
}

function k8s-shell {
    kubectl run "$@-test-shell" --rm -i --tty --image ubuntu -- /bin/bash
    kubectl delete pod "$@-test-shell"
}

function pet-run() {
  pet search | bash -xe
}

# https://github.com/gokcehan/lf?tab=readme-ov-file#installation
function lfcd {
  cd "$(command lf -print-last-dir "$@")"
}
