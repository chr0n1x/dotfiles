install-nord:
	-git clone \
	  https://github.com/arcticicestudio/nord-dircolors.git \
	  $(shell echo $$HOME)/Code/arcticicestudio/nord-dircolors
	-ln -vs "$(shell echo $$HOME)/Code/arcticicestudio/nord-dircolors/src/dir_colors" ~/.dir_colors

# https://github.com/ohmyzsh/ohmyzsh#unattended-install
install-omzsh:
	-sh -c \
	  "$$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
	  "" --unattended
	-rm ~/.zshrc

install-omz-plugins:
	-git clone https://github.com/zsh-users/zsh-autosuggestions $${ZSH_CUSTOM:-$$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
	-git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $${ZSH_CUSTOM:-$$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
	-git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git $${ZSH_CUSTOM:-$$HOME/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting
	-git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete.git $${ZSH_CUSTOM:-$$HOME/.oh-my-zsh/custom}/plugins/zsh-autocomplete

install-zsh: install-nord install-omzsh install-omz-plugins
