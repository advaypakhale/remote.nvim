local transport = require("remote.transport")

local M = {}

---@class remote.transport.Docker : remote.Transport
---@field container string
local Docker = setmetatable({}, { __index = transport.defaults })
Docker.__index = Docker

---@param container string Name or ID
---@return remote.transport.Docker
function M.new(container)
  return setmetatable({ container = container }, Docker)
end

---@param opts? { tty?: boolean }
function Docker:argv(script, opts)
  local flags = opts and opts.tty and "-it" or "-i"
  return { "docker", "exec", flags, self.container, "/bin/sh", "-c", script }
end

function Docker:label()
  return self.container
end

---@return string[] containers Running containers, empty when docker is unavailable
function M.containers()
  if vim.fn.executable("docker") == 0 then
    return {}
  end

  local result = transport.local_exec({ "docker", "ps", "--format", "{{.Names}}" })
  if result.code ~= 0 then
    return {}
  end
  return vim.split(vim.trim(result.stdout), "\n", { trimempty = true })
end

return M
