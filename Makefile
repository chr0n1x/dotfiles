# if on linux:
#
#   apt install -y git curl build-essential
#   make linux default
#
# if any commands fail, you might have to run an apt-get as sudo first
default: install-zsh setup-git stow chsh

linux-arm64: install-zsh setup-git nvim-linux-arm64 submodules-over-https stow chsh

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
	rm -rf ~/.local/bin/nvim ~/.local/opt/nvim*
	curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
	mkdir -p ~/.local/opt
	tar -C ~/.local/opt -xzf nvim-linux64.tar.gz
	mkdir -p ~/.local/bin
	ln -vs ~/.local/opt/nvim-linux64/bin/nvim ~/.local/bin/nvim
	rm nvim-linux64.tar.gz
	# If this fails run it as sudo
	apt-get install direnv git gh zsh ripgrep fzf bat tree stow zoxide tmux


nvim-linux-arm64:
	rm -rf ~/.local/bin/nvim ~/.local/opt/nvim*
	curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.tar.gz
	mkdir -p ~/.local/opt
	tar -C ~/.local/opt -xzf nvim-linux-arm64.tar.gz
	mkdir -p ~/.local/bin
	ln -vs ~/.local/opt/nvim-linux64/bin/nvim ~/.local/bin/nvim
	rm nvim-linux-arm64.tar.gz
	# If this fails run it as sudo
	apt-get install direnv git gh zsh ripgrep fzf bat tree stow zoxide tmux


submodules-over-https:
	git clone https://github.com/tmux-plugins/tpm.git .tmux/plugins/tpm
	git clone https://github.com/chr0n1x/neovim-configs .config/nvim


# some LSP things require nodejs :(
install-nvm-lts:
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
