local M = {}

---@param opts remote.Config?
function M.setup(opts)
  require("remote.config").setup(opts)
end

---@param spec string An ssh host, or `docker:<container>`
---@param conn_opts string[]? Passed through to `ssh`
---@return remote.Transport
local function resolve(spec, conn_opts)
  local container = spec:match("^docker:(.+)$")
  if container then
    if conn_opts and #conn_opts > 0 then
      vim.notify("remote.nvim: extra arguments only apply to ssh targets", vim.log.levels.WARN)
    end
    return require("remote.transport.docker").new(container)
  end
  return require("remote.transport.ssh").new(spec, conn_opts)
end

local cache = { specs = nil, labels = nil, at = 0 }

---Scanning the ssh config and listing containers is too slow to repeat per
---keystroke, and completion is called on every one.
local function discover()
  local now = vim.uv.now()
  if cache.specs and now - cache.at < 2000 then
    return cache.specs, cache.labels
  end

  local ssh_config = require("remote.ssh_config")
  local specs, labels = {}, {}

  for _, host in ipairs(ssh_config.hosts(require("remote.config").get().ssh_config_path)) do
    table.insert(specs, host.host)
    labels[host.host] = ssh_config.format(host)
  end
  for _, container in ipairs(require("remote.transport.docker").containers()) do
    local spec = "docker:" .. container
    table.insert(specs, spec)
    labels[spec] = spec
  end

  cache = { specs = specs, labels = labels, at = now }
  return specs, labels
end

---@return string[] specs Completion candidates
function M.targets()
  return (discover())
end

local function pick(prompt, fn)
  local specs, labels = discover()
  if #specs == 0 then
    vim.notify("remote.nvim: no hosts in ssh config and no running containers", vim.log.levels.WARN)
    return
  end

  vim.ui.select(specs, {
    prompt = prompt,
    format_item = function(spec)
      return labels[spec]
    end,
  }, function(choice)
    if choice then
      fn(choice)
    end
  end)
end

---@param spec string? Prompts when omitted
---@param conn_opts string[]?
---@param force boolean? Reinstall binaries even if the manifest matches
function M.install(spec, conn_opts, force)
  if spec == nil then
    return pick("Install Neovim on:", function(chosen)
      M.install(chosen, conn_opts, force)
    end)
  end
  require("remote.install").run(resolve(spec, conn_opts), force)
end

---@param spec string? Prompts when omitted
---@param confirmed boolean? Skip the confirmation prompt
function M.cleanup(spec, confirmed)
  if spec == nil then
    return pick("Remove remote.nvim from:", function(chosen)
      M.cleanup(chosen, confirmed)
    end)
  end

  local prefix = require("remote.config").get().prefix
  if not confirmed and vim.fn.confirm(("Remove %s from %s?"):format(prefix, spec), "&Yes\n&No", 2) ~= 1 then
    return
  end
  require("remote.install").cleanup(resolve(spec))
end

return M
