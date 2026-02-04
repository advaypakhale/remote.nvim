# remote.nvim

Deploy your Neovim configuration to remote machines over SSH. Downloads Neovim, ripgrep, and fd, transfers them along with your config, and sets up an isolated environment that won't interfere with anything on the remote host.

## Requirements

- **Local:** ssh, curl, tar (rsync recommended but optional)
- **Remote:** Linux x86_64 (all tools are provided — nothing needs to be pre-installed)
- **Neovim:** >= 0.8.0

## Installation

```lua
-- lazy.nvim
{
  "advaypakhale/remote.nvim",
  config = function()
    require("remote").setup({
      -- default; can also be a list: { "~/.ssh/config", "~/.ssh/work_config" }
      ssh_config_path = "~/.ssh/config",
    })
  end,
}
```

## Usage

### Interactive (host picker from SSH config)

```vim
:RemoteSetup       " set up Neovim on a remote host
:RemoteSync        " sync local config changes to a remote host
:RemoteCleanup     " remove everything the plugin installed on a remote host
```

### Direct

```vim
:RemoteSetup myserver
:RemoteSetup user@host --ssh-opts "-i ~/.ssh/key.pem -p 2222"
:RemoteSync myserver --config-dir ~/custom-nvim
:RemoteCleanup myserver --yes
```

Arguments after the host are passed directly to the underlying shell script.

### On the remote host

```bash
~/.remote-nvim/rnvim [file]
```

Plugins will install automatically on first launch.

## What gets deployed

Everything is installed under `~/.remote-nvim/` on the remote host:

- `bin/nvim` — Neovim AppImage (latest release)
- `bin/rg` — ripgrep 14.1.0 (only added to PATH if not already installed)
- `bin/fd` — fd 10.3.0 (only added to PATH if not already installed)
- `config/nvim/` — your Neovim configuration (excluding `.git`, `.gitignore`, `lazy-lock.json`)
- `rnvim` — wrapper script that runs Neovim with isolated XDG directories

The remote environment is fully isolated — XDG_CONFIG_HOME, XDG_DATA_HOME, and XDG_STATE_HOME are all scoped to `~/.remote-nvim/`.

## Local cache

Binaries are cached at `${XDG_DATA_HOME:-~/.local/share}/nvim/remote.nvim/cache/` so they aren't re-downloaded on every setup. Delete this directory to force a fresh download.

## Standalone usage

The shell script can be used independently of Neovim:

```bash
./scripts/remote-nvim.sh setup user@host
./scripts/remote-nvim.sh sync user@host
./scripts/remote-nvim.sh cleanup user@host
./scripts/remote-nvim.sh --help
```

## Limitations

- Remote host must be **Linux x86_64** (the downloaded binaries are architecture-specific)
- The Neovim AppImage URL tracks `latest` — delete the local cache to pick up new Neovim releases
- SSH config parsing handles common cases (Host, HostName, User, Include) but not the full spec

## License

MIT
