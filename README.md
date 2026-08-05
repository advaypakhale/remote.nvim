<div align="center">

# remote.nvim

Deploy Neovim and your config to remote development environments

[![CI](https://img.shields.io/github/actions/workflow/status/advaypakhale/remote.nvim/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/advaypakhale/remote.nvim/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/advaypakhale/remote.nvim?style=flat-square)](https://github.com/advaypakhale/remote.nvim/releases)
[![Neovim](https://img.shields.io/badge/Neovim-0.11%2B-57A143?style=flat-square&logo=neovim&logoColor=white)](https://neovim.io)
[![License](https://img.shields.io/github/license/advaypakhale/remote.nvim?style=flat-square)](LICENSE)

[Install](#install) &bull; [Usage](#usage) &bull; [Configuration](#configuration) &bull; [Documentation](doc/remote-nvim.txt)

</div>

remote.nvim installs a Neovim binary, your config, and any tools you declare into a single directory under `$HOME` on
the target. Its config, data, state and cache directories all live in there, so an existing Neovim on the target keeps
its own. It never needs root, and everything it does to the target can be undone by deleting that one directory. You
start Neovim on the target yourself, whenever you want it.

## Features

- Installs to any host you can `ssh` to, or any running Docker container
- Installs the same Neovim version you run locally, matched to the target's OS and architecture
- Works on targets without network access; downloads happen locally and are sent over the connection
- Re-run it to push config changes; binaries are only downloaded when the version changes
- Installs extra binaries, such as `ripgrep` or `fd`, if you ask it to
- About a thousand lines of Lua, no plugin dependencies

## Requirements

Neovim 0.11+, `ssh`, `tar` and `curl` locally. A POSIX shell and the usual utilities on the target,
including `tar` (busybox is fine). `docker` for container targets.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "advaypakhale/remote.nvim", opts = {} }
```

With `vim.pack`:

```lua
vim.pack.add({ "https://github.com/advaypakhale/remote.nvim" })
require("remote").setup({})
```

## Usage

```vim
:Remote                              " pick a target from a list
:Remote install myserver             " ssh host
:Remote install docker:mycontainer   " running container
:Remote install box -p 2222          " extra arguments go to ssh
:Remote! install myserver            " reinstall binaries
:Remote cleanup myserver             " remove the install directory
```

Completion offers hosts from your ssh config and running containers.

Installing prints the command to start Neovim on the target. Run that in your own terminal:

```sh
ssh -t myserver ~/.remote-nvim/rnvim
docker exec -it mycontainer ~/.remote-nvim/rnvim
```

Re-run `:Remote install` after changing your config to push it again.

## Configuration

All options are optional. Defaults shown:

```lua
require("remote").setup({
  ssh_config_path = { "~/.ssh/config" },  -- files scanned for host names
  config_dir = nil,                       -- nil uses stdpath("config")
  prefix = "~/.remote-nvim",              -- install directory on the target
  app_name = "nvim",                      -- NVIM_APPNAME on the target
  nvim_version = nil,                     -- nil matches your local Neovim
  exclude = { ".git" },                   -- excluded from the copied config
  copy_dirs = {},                         -- extra directories to copy
  tools = {},                             -- extra binaries to install
})
```

See `:help remote-nvim-configuration`.

## Extra tools

Only Neovim and your config are copied by default. To install other binaries on the target:

```lua
tools = {
  rg = {
    version = "14.1.1",
    bin = "rg",
    url = function(os, arch)
      return ("https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-%s-unknown-%s-musl.tar.gz")
        :format(arch, os)
    end,
  },
}
```

`url` receives the target's platform, where `os` is `linux` or `macos` and `arch` is `x86_64` or `arm64`. A tool is
added to the target's `PATH` only when the target does not already have it.

## Targets without network access

Neovim and your tools are downloaded by the target when it has `wget` or `curl`, and otherwise downloaded locally and
sent over the connection.

Plugin managers fetch plugins with `git`, which needs network access on the target. When there is none, copy the
plugins you already have:

```lua
copy_dirs = { data = { "lazy" } }
```

The key names a Neovim directory (`data`, `state` or `cache`) and the values are subdirectories inside it.

A data directory can contain binaries built for your platform, such as treesitter parsers and Mason-installed
servers. Copying those to a target with a different architecture produces binaries that will not run, and a warning
is shown when the platforms differ.

## Limitations

- Windows is not supported as the local machine.
- `devcontainer.json` is not supported. Attaching to a running container works.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
