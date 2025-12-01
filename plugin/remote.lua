-- remote.nvim plugin registration
-- This file is automatically loaded by Neovim

if vim.fn.has("nvim-0.8.0") == 0 then
  vim.api.nvim_err_writeln("remote.nvim requires Neovim >= 0.8.0")
  return
end

-- Prevent loading twice
if vim.g.loaded_remote_nvim then
  return
end
vim.g.loaded_remote_nvim = 1

-- Register commands
vim.api.nvim_create_user_command("RemoteSetup", function(opts)
  require("remote").setup_command(opts.args)
end, {
  nargs = "*",
  desc = "Setup Neovim on remote host",
})

vim.api.nvim_create_user_command("RemoteSync", function(opts)
  require("remote").sync_command(opts.args)
end, {
  nargs = "*",
  desc = "Sync config to remote host",
})

vim.api.nvim_create_user_command("RemoteCleanup", function(opts)
  require("remote").cleanup_command(opts.args)
end, {
  nargs = "*",
  desc = "Remove Neovim from remote host",
})
