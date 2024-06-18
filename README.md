dotfiles
=========

If you just want to run `nvim` though I highly recommend that you take a look at [my NeoVim starter template](https://github.com/chr0n1x/neovim-template) to begin your NeoVim journey 🥳

# Requirements

- NEOVIM. Just use Neovim, it'll save you a lot of configuration trouble.
- `stow`
- Specific plugins require `python`. So make sure that you have `python` installed, along with `pip`

# Installation

- make sure that you have access to the requirements above. macOS you can use `make macos-install`
    - check out the `linux` target in `Makefile` to see what's needed
    - if you have access to `apt-get`, the `linux` target should work out of the box
- run `make`; this will:
    - install omzsh, the nord color scheme
    - set up some git defaults (colors and whatnot, to see what check out `make/git.mk`
    - symlink everything in here to your home dir (`~/`) via `stow`

# Aliases

This setup also comes with some aliases, out of the box

```bash
docker run -v $(pwd):/root/workspace --workdir /root/workspace --rm -ti "$@"
```

This allows me to mount my current working directory into `/root/workspace` for any arbitrary container. So for example if I am working on a python project and I'm in that project directory, I just use `dex python:3.6` and I am automatically dropped into a shell environment that has all development tools necessary to work on that project (e.g.: python runtime, `pip`, etc).

## Bash / Zsh

```bash
function dex {
  if docker version &> /dev/null; then
    docker run -v $(pwd):/root/workspace --workdir /root/workspace --rm -ti "$@"
  else
    echo "Docker isn't installed or has not been started."
  fi
}
