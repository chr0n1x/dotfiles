function dex {
  local container
  if command -v podman &> /dev/null && podman version &> /dev/null; then
    container=podman
  elif command -v docker &> /dev/null && docker version &> /dev/null; then
    container=docker
  else
    echo "Neither podman nor docker is available."
    return 1
  fi
  $container run -v $PWD:/root/workspace --workdir /root/workspace --rm -ti "$@"
}
