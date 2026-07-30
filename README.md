# remote.nvim

Run your local Neovim on a remote machine or container, without touching anything already installed there.

```vim
:Remote connect myserver
```

A Neovim binary, your config, and any tools you declare are copied into a single directory under `$HOME` on the
target, and Neovim runs there. There is no client/server split, so nothing has to stay protocol-compatible between
your machine and the target.

Requires Neovim 0.11+ and `ssh` locally, plus `sh` and `tar` on the target (busybox versions work). `curl` is used
locally only when the target cannot download for itself. No plugin dependencies.

## Install

No `setup()` call needed.

```lua
{ "advaypakhale/remote.nvim" }
```

`:checkhealth remote` verifies your local tooling.

## Usage

```vim
:Remote                              " pick a target, provision, launch
:Remote connect myserver             " ssh host
:Remote connect docker:mycontainer   " running container
:Remote connect box -p 2222          " extra args go to ssh
:Remote! connect myserver            " force a binary reinstall
:Remote cleanup myserver             " remove the install prefix
```

Targets complete from your ssh config, following `Include` and globs, and from `docker ps`.

Provisioning is idempotent, so there is no separate sync command. Re-run `:Remote connect` to push config changes;
binaries are fetched only when the version on the target differs from the one you want.

## Configuration

Optional. Set `vim.g.remote_nvim` to a table or a function returning one. `require("remote").setup()` also works and
takes precedence.

```lua
vim.g.remote_nvim = {
  ssh_config_path = { "~/.ssh/config" },  -- files scanned for host names
  prefix = "~/.remote-nvim",              -- install root on the target
  app_name = "nvim",                      -- NVIM_APPNAME on the target
  nvim_version = nil,                     -- nil = match the local Neovim
  exclude = { ".git" },                   -- excluded from the config tree
  copy_dirs = {},                         -- extra directories to copy
  tools = {},                             -- extra binaries to ship
}
```

`:help remote-nvim-configuration` documents each option.

## Extra tools

Only Neovim and your config are copied by default. Declare anything else you want on the target:

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

`url` is called with the target's platform: `os` is `linux` or `macos`, `arch` is `x86_64` or `arm64`. Tools are put
on the target's `PATH` only if it does not already have them, so system installs are never shadowed.

## Air-gapped targets

Neovim and your tools are downloaded by the target when it has `wget` or `curl`, and otherwise downloaded locally and
streamed over the connection. Neither case needs configuration.

Plugins are different, because every plugin manager fetches them with `git` and that needs network access on the
target. When there is none, copy the plugins you already have:

```lua
copy_dirs = { data = { "lazy" } }
```

The key names a Neovim directory (`data`, `state` or `cache`) and the values are subdirectories inside it. Nothing
here knows what `lazy` is, so `vim.pack`, paq or a hand-rolled `pack/` layout behave the same way.

Note that a data directory can contain binaries compiled for your platform, such as treesitter parsers and Mason
servers. Copying those to a different architecture produces binaries that will not run, so a warning is shown when
the platforms differ.

## Limitations

- musl targets are refused. Neovim publishes no musl build, so Alpine gets an error instead of a glibc binary that
  cannot load.
- Windows is unsupported as the local machine. It needs a POSIX shell, and Windows OpenSSH has no connection
  multiplexing.
- `devcontainer.json` is out of scope. Attaching to a running container works; image builds, Features and lifecycle
  hooks do not.

`:help remote-nvim-internals` describes how it works.

## License

MIT
