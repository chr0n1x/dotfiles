FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl make ca-certificates zsh direnv zoxide \
  && rm -rf /var/lib/apt/lists/*

# Install zunit + revolver
RUN git clone https://github.com/zunit-zsh/zunit /tmp/zunit && \
      cd /tmp/zunit && ./build.zsh && chmod u+x ./zunit && cp ./zunit /usr/local/bin/

RUN git clone https://github.com/molovo/revolver /tmp/revolver && \
      chmod u+x /tmp/revolver/revolver && cp /tmp/revolver/revolver /usr/local/bin/

# Install OMZ (unattended)
RUN sh -c \
	"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
	"" --unattended

WORKDIR /app
COPY . /app
RUN make install-omz-plugins

# Symlink so $HOME/.config points to /app/.config (where our scripts live)
RUN ln -sf /app/.config /root/.config

ENV TERM=linux
ENV SHELL=/usr/bin/zsh

ENTRYPOINT ["zsh", "-c", "cd /app && source /app/.zshrc && zunit"]
