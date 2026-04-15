# if on linux:
#
#   apt install -y git curl build-essential
#   make
#
# if any commands fail, you might have to run an apt-get as sudo first
# also assumes that your SSH keys are in place
default: linux-compile-nvim linux install-zsh setup-git git-signing stow chsh


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
	sudo apt-get install direnv git zsh ripgrep fzf bat tree stow zoxide tmux cmake xsel cryptsetup cifs-utils

	# pretty cli things
	sudo mkdir -p /etc/apt/keyrings
	curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
	echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
	sudo apt update && sudo apt install glow gum
	curl https://sh.rustup.rs -sSf | sh
	$(shell $$HOME/.cargo/bin/cargo install git-delta)

	# cluster wrangling
	curl -sL https://talos.dev/install | sh
	# pick your poison
	# sudo snap install kubectl --classic
	curl -LO "https://dl.k8s.io/release/$(shell curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
	curl -LO "https://dl.k8s.io/release/$(shell curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl.sha256"
	echo "$$(cat kubectl.sha256)  kubectl" | sha256sum --check
	sudo install -o kran -g kran -m 0755 kubectl /usr/local/bin/kubectl
	kubectl version --client
	# optional things with krew and whatnot - do it yourself
	# https://krew.sigs.k8s.io/docs/user-guide/setup/install/
	# kubectl krew install ctx ns cnpg cert-manager

	# AI things
	curl -fsSL https://claude.ai/install.sh | bash
	curl -fsSL https://ollama.com/install.sh | sh
	sudo systemctl disable ollama # only use CLI

# doesnt actually work - made to copy-paste
install-krew:
	(
		set -x; cd "$(mktemp -d)" &&
		OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
		ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
		KREW="krew-${OS}_${ARCH}" &&
		curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
		tar zxvf "${KREW}.tar.gz" &&
		./"${KREW}" install krew
	)
	kubectl krew install ctx ns cnpg cert-manager

# run this w/ sudo
linux-compile-nvim:
	rm -rf ~/.local/opt/neovim || :
	git clone https://github.com/neovim/neovim.git ~/.local/opt/neovim
	sudo apt-get install ninja-build gettext cmake curl build-essential git
	cd ~/.local/opt/neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo && sudo make install

submodules-over-https:
	git clone https://github.com/tmux-plugins/tpm.git .tmux/plugins/tpm
	git clone https://github.com/chr0n1x/neovim-configs .config/nvim


# some LSP things require nodejs :(
install-nvm-lts:
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
