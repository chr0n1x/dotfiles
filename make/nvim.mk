packer-setup:
	nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
	nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerInstall'
	nvim --headless -c 'autocmd User COQdeps quitall'

install-nvim: packer-setup
