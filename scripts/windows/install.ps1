# 1 install choco via winget (which should come installed by default on win11)
# 2 run choco as an admin, install git
# 3 clone this repo, set up any keys if required - gpg, signing, ssh, etc
# 4 run this script as an admin
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
#
# REMEMBER TO GIT CONFIG YOURSELF

# clone down neovim and friends
git submodule update --init

# symlink local nvim config repo to windows user home
New-Item -Path "${HOME}\AppData\Local\nvim" -ItemType SymbolicLink -Value "$((Get-Item .).FullName)\.config\nvim"

# symlink user profile to the one in here AHHHH
new-item -type file -path $profile -force
New-Item -Path "${profile}" -ItemType SymbolicLink -Value "$((Get-Item .).FullName)\scripts\windows\profile.ps1"
