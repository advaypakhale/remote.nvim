if vim.fn.has("nvim-0.11.0") == 0 then
  vim.notify("remote.nvim requires Neovim >= 0.11", vim.log.levels.ERROR)
  return
end

if vim.g.loaded_remote_nvim then
  return
end
vim.g.loaded_remote_nvim = 1

local subcommands = {
  install = function(args, opts)
    require("remote").install(args[1], vim.list_slice(args, 2), opts.bang)
  end,
  cleanup = function(args)
    require("remote").cleanup(args[1])
  end,
}

vim.api.nvim_create_user_command("Remote", function(opts)
  local name = opts.fargs[1] or "install"
  local impl = subcommands[name]
  if impl == nil then
    vim.notify(("remote.nvim: unknown subcommand '%s'"):format(name), vim.log.levels.ERROR)
    return
  end
  impl(vim.list_slice(opts.fargs, 2), opts)
end, {
  nargs = "*",
  bang = true,
  desc = "Transplant Neovim onto an ssh host or container",
  complete = function(lead, line)
    local words = vim.split(vim.trim(line), "%s+", { trimempty = true })
    local completing_subcommand = #words - (lead == "" and 0 or 1) <= 1

    local candidates = completing_subcommand and vim.tbl_keys(subcommands) or require("remote").targets()
    table.sort(candidates)

    return vim.tbl_filter(function(candidate)
      return vim.startswith(candidate, lead)
    end, candidates)
  end,
})
