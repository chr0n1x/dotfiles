default: install-zsh link-nvim-configs setup-git

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

include make/*.mk

clean:
	rm -rf nvim/plugin ~/.local/share/nvim ~/.config/nvim ~/.cache/nvim ~/.config/nvim ~/.config/zsh ~/.zshrc

macos-install:
	which brew /dev/null || /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	brew install ag direnv git gh nvim z zsh ripgrep fzf secretive bat tree fd
	pip3 install virtualenv

# TODO: clean this up, adding here for reference later
linux:
	rm -rf ~/.local/bin/nvim ~/.local/opt/nvim*
	curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
	mkdir -p ~/.local/opt
	tar -C ~/.local/opt -xzf nvim-linux64.tar.gz
	mkdir -p ~/.local/bin
	ln -vs ~/.local/bin/nvim-linux64/bin/nvim ~/.local/bin/nvim
	rm nvim-linux64.tar.gz
