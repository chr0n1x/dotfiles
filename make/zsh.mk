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

install-zsh: install-nord install-omzsh
