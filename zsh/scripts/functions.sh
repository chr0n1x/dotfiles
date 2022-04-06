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

function dk8s {
  dex --hostname docker-k8s-dev \
      --network host \
      -e AWS_SECRET_ACCESS_KEY \
      -e AWS_SESSION_TOKEN \
      -e AWS_SECURITY_TOKEN \
      -e AWS_ACCESS_KEY_ID \
      -e AWS_DEFAULT_REGION \
      -e AWS_SDK_LOAD_CONFIG \
      docker-ethos-release.dr-uw2.adobeitc.com/adobe-platform/k8s-toolbox:latest

}
