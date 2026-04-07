setup-git:
	git config --global rebase.autosquash true
	git config --global color.ui true
	git config --global core.editor nvim
	git config --global core.pager cat
	git config --global --replace-all core.pager "less -F -X"

git-signing:
	git config --global commit.gpgsign true
	git config --global gpg.format ssh
	git config --global user.signingkey ~/.ssh/id_rsa.pub

git-delta:
	git config --global core.pager delta
	git config --global interactive.diffFilter 'delta --color-only'
	git config --global delta.navigate true
	git config --global delta.dark true  # or `delta.light true`, or omit for auto-detection
	git config --global merge.conflictStyle zdiff3
