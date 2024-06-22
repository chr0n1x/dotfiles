choco install neovim fzf ripgrep python mingw zoxide gnupg

# make sure to create and setup a gpg key for this
# get location of installed gpg via
#   where.exe gpg.exe
git config --global gpg.program "C:\Program Files (x86)\gnupg\bin\gpg.exe"
# can instead use SSH to sign
#
#   git config --global user.signingkey C:\Users\HeiLo\.ssh\id_rsa.pub
#
# make sure to add the pub key as a SIGNING key.
# also - might be better to generate a different key

mkdir $$HOME\OneDrive\Documents\WindowsPowerShell

# symlink local nvim config repo to windows user home
New-Item -Path "${HOME}\AppData\Local\nvim" -ItemType SymbolicLink -Value "$((Get-Item .).FullName)\.config\nvim"

# symlink user profile to the one in here AHHHH
New-Item -Path "${profile}" -ItemType SymbolicLink -Value "$((Get-Item .).FullName)\scripts\windows\profile.ps1"
