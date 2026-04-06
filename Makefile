# if on linux:
#
#   apt install -y git curl build-essential
#   make linux default
#
# if any commands fail, you might have to run an apt-get as sudo first
default: install-zsh setup-git linux git-signing stow chsh

# rpi or linux in general
linux-arm64: submodules-over-https install-zsh setup-git linux linux-compile-nvim stow chsh

tag := chr0n1x/dev-env:latest

build:
	docker build --tag $(tag) .

dev:
	@echo "Building container for local dev if DNE"
	@docker inspect $(tag) || $(MAKE) build
	docker run --rm -ti \
	  -v $(shell pwd):/workspace \
	  -w /workspace \
	  --entrypoint zsh $(tag)

# assume that stow is already installed (check the macos-install target below)
stow:
	@git submodule update --init || \
	  (echo "Could not install submodules. If you do not have SSH set up, clone via 'make install-submodules'" && \
	  exit 1)
	stow -d $(shell pwd) -t ~/ .


chsh:
	chsh $(shell whoami) --shell $(shell which zsh)


include make/*.mk

clean:
	rm -rf nvim/plugin ~/.local/share/nvim ~/.config/nvim ~/.cache/nvim ~/.config/nvim ~/.config/zsh ~/.zshrc

macos-install:
	which brew /dev/null || /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	brew install ag direnv git gh nvim z zsh ripgrep fzf secretive bat tree fd stow zoxide tmux knqyf263/pet/pet
	pip3 install virtualenv

# TODO: clean this up, adding here for reference later
linux:
	# direnv - for all .envrc shell secrets, PER dir
	# git - cause git
	# zsh - my shell of choice
	# ripgrep - faster grep
	# fzf - nice fuzzy search
	# bat - better cat
	# tree - nice dir listing
	# stow - for all .conf files and symlinks in my home directory
	# zoxide - cd but with fuzzy matching
	# tmux - cause what you doing without it
	# cmake - for compiling nvim
	# xsel - copy-paste from remote host to host terminal
	# cifs-utils to mount things via fstab
	#
	# TODO: go back to this when 0.11 packages officially get released for arm7
	# rm -rf ~/.local/bin/nvim ~/.local/opt/nvim*
	# curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
	# mkdir -p ~/.local/opt
	# tar -C ~/.local/opt -xzf nvim-linux64.tar.gz
	# mkdir -p ~/.local/bin
	# ln -vs ~/.local/opt/nvim-linux64/bin/nvim ~/.local/bin/nvim
	# rm nvim-linux64.tar.gz
	sudo apt-get install direnv git zsh ripgrep fzf bat tree stow zoxide tmux cmake xsel cryptsetup cifs-utils

	# pretty cli things
	sudo mkdir -p /etc/apt/keyrings
	curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
	echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
	sudo apt update && sudo apt install glow

	# cluster wrangling
	curl -sL https://talos.dev/install | sh
	# pick your poison
	snap install kubectl --classic
	kubectl version --client
	# optional things with krew and whatnot - do it yourself
	# https://krew.sigs.k8s.io/docs/user-guide/setup/install/
	# kubectl krew install ctx ns cnpg cert-manager

	# AI things
	curl -fsSL https://claude.ai/install.sh | bash
	curl -fsSL https://ollama.com/install.sh | sh
	systemctl disable ollama # only use CLI

nvim-linux-arm64:
	rm -rf ~/.local/bin/nvim ~/.local/opt/nvim*
	curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.tar.gz
	mkdir -p ~/.local/opt
	tar -C ~/.local/opt -xzf nvim-linux-arm64.tar.gz
	mkdir -p ~/.local/bin
	ln -vs ~/.local/opt/nvim-linux64/bin/nvim ~/.local/bin/nvim
	rm nvim-linux-arm64.tar.gz
	# If this fails run it as sudo
	apt-get install direnv git gh zsh ripgrep fzf bat tree stow zoxide tmux cmake


# run this w/ sudo
linux-compile-nvim:
	rm -rf ~/.local/opt/neovim || :
	git clone https://github.com/neovim/neovim.git ~/.local/opt/neovim
	cd ~/.local/opt/neovim
	make CMAKE_BUILD_TYPE=RelWithDebInfo
	make install


submodules-over-https:
	git clone https://github.com/tmux-plugins/tpm.git .tmux/plugins/tpm
	git clone https://github.com/chr0n1x/neovim-configs .config/nvim


# some LSP things require nodejs :(
install-nvm-lts:
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
