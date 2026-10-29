#!/usr/bin/env bash
set -euo pipefail
ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')
curl -fsSL "https://go.dev/dl/go1.24.4.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tar.gz
rm /tmp/go.tar.gz
