packer-setup:
	nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
	nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerInstall'
	nvim --headless -c 'autocmd User COQdeps quitall'

link-nvim-configs:
	-mkdir ~/.config
	-ln -vs $(shell pwd)/nvim $(shell echo $$HOME)/.config/nvim

install-nvim: link-nvim-configs packer-setup
