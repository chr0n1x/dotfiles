FROM alpine:latest

RUN apk add --no-cache \
    zoxide \
    direnv \
    zsh \
    git \
    bash \
    make \
    curl \
    tmux \
    ncurses

RUN git clone https://github.com/zunit-zsh/zunit && \
      cd ./zunit && \
      ./build.zsh && \
      chmod u+x ./zunit && \
      cp ./zunit /usr/local/bin/.

RUN git clone https://github.com/molovo/revolver revolver && \
      chmod u+x revolver/revolver && \
      mv revolver/revolver /usr/local/bin/.

RUN sh -c \
	"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
	"" --unattended

WORKDIR /app
COPY Makefile /app/Makefile
COPY make /app/make
# TODO: yes yes - change to diff user later
COPY .config/zsh /root/.config/zsh
RUN make install-omz-plugins

# uhhh iunno if this works
ENV TERM=linux
ENV SHELL=/usr/bin/zsh

# Run zunit by default with omz sourced
ENTRYPOINT ["zsh", "-c", "cd /app && source /root/.zshrc && zunit"]
