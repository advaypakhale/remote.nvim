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

function Docker:argv(script)
  return { "docker", "exec", "-i", self.container, "/bin/sh", "-c", script }
end

---@return string command The user runs this themselves, in their own terminal
function Docker:launch_hint(command)
  return ("docker exec -it %s %s"):format(self.container, command)
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
