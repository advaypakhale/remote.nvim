# remote.nvim

A Neovim plugin for easily deploying and syncing your Neovim configuration to remote machines via SSH.

## Installation

Using your preferred plugin manager:

```lua
-- lazy.nvim
{
  "advaypakhale/remote.nvim",
  config = function()
    require("remote").setup({
      ssh_config_path = "~/.ssh/config",  -- or { "~/.ssh/config", "~/.ssh/work_config" }
    })
  end,
}
```

## Usage

### Interactive Mode (with picker)

```vim
:RemoteSetup    " Opens picker to select host from SSH config
:RemoteSync     " Opens picker to select host to sync neovim config
:RemoteCleanup  " Opens picker to select host to cleanup everything set up on host by the plugin
```

### Direct Mode (with arguments)

```vim
:RemoteSetup myserver
:RemoteSetup user@host --ssh-opts "-i ~/.ssh/key.pem -p 2222"
:RemoteSync myserver --config-dir ~/custom-nvim
:RemoteCleanup myserver --yes
```

All arguments after the command are passed directly to the underlying bash script.

## Directory Structure

```
remote.nvim/
├── plugin/          # Plugin registration
├── lua/remote/      # Lua modules
│   ├── init.lua     # Main logic
│   ├── config.lua   # Configuration
│   ├── ssh.lua      # SSH config parser
│   └── ui.lua       # Floating terminal
└── scripts/         # Shell scripts
    ├── remote-nvim.sh  # Main deployment script
    └── rnvim           # Remote wrapper script
```

## Cache Location

Binaries (Neovim, ripgrep, fd) are cached at:
- `~/.local/share/nvim/remote.nvim/cache` (or `$XDG_DATA_HOME/nvim/remote.nvim/cache`)

This allows the cache to persist across plugin updates.

## Remote Usage

After setup, SSH into your remote host and run:
```bash
~/.remote-nvim/rnvim
```
