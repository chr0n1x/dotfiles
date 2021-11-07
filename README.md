dotfiles
=========

[![Build Status](https://api.travis-ci.com/chr0n1x/dev-env.svg?branch=main)](https://app.travis-ci.com/github/chr0n1x/dotfiles)

My Neovim and Zsh setups, wrapped into a docker container (automated build). Also includes other common dev tools such as [the silver searcher (aka: ag)](https://github.com/ggreer/the_silver_searcher). A full list is forthcoming since I'm still in the process of adding things to this project.

I did this because I've had to switch machines WAY too many times. Another reason though is because I wanted a similar development experience between my MacOS, Linux & Windows machines so I figured that docker was the way to go.

If you just want to run `vim` though I highly recommend that you take a look at [my NeoVim starter template](https://github.com/chr0n1x/neovim-template) to begin your NeoVim journey 🥳

# Requirements

NEOVIM. Just use Neovim, it'll save you a lot of configuration trouble.

## Required Plugins

Specific plugins require `python`. So make sure that you have `python` installed, along with `pip`

# Aliases

I personally like to have two separate aliases, only one of which directly uses this container. The first is the `dex` alias (short for `docker exec`). I like to use this as a shortcut for:

```bash
docker run -v $(pwd):/root/workspace --workdir /root/workspace --rm -ti "$@"
```

This allows me to mount my current working directory into `/root/workspace` for any arbitrary container. So for example if I am working on a python project and I'm in that project directory, I just use `dex python:3.6` and I am automatically dropped into a shell environment that has all development tools necessary to work on that project (e.g.: python runtime, `pip`, etc).

However, because my VIM installation is a bit more involved and needs tools that may be separate from whatever language I'm working in I have the `dvim` alias (short for `docker-vim`). This alias uses `dex` in conjunction with this container.

## Bash / Zsh

```bash
function dex {
  if docker version &> /dev/null; then
    docker run -v $(pwd):/root/workspace --workdir /root/workspace --rm -ti "$@"
  else
    echo "Docker isn't installed or has not been started."
  fi
}

function dvim {
    dex --entrypoint "vim" chr0n1x/dev-env
}
```
