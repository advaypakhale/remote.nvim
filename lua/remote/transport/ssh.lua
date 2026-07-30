local transport = require("remote.transport")

local M = {}

local CONTROL_PATH = "/tmp/rnvim-%C"

---@class remote.transport.SSH : remote.Transport
---@field host string
---@field conn_opts string[]
local SSH = setmetatable({}, { __index = transport.defaults })
SSH.__index = SSH

---@param host string
---@param conn_opts string[]? Extra arguments passed through to `ssh`
---@return remote.transport.SSH
function M.new(host, conn_opts)
  return setmetatable({ host = host, conn_opts = conn_opts or {} }, SSH)
end

function SSH:_base(master)
  local argv = {
    "ssh",
    "-o",
    "ControlMaster=" .. master,
    "-o",
    "ControlPath=" .. CONTROL_PATH,
    "-o",
    "ControlPersist=60",
    "-o",
    "ConnectTimeout=10",
  }
  return vim.list_extend(argv, self.conn_opts)
end

function SSH:argv(script)
  local argv = self:_base("auto")
  vim.list_extend(argv, { self.host, "/bin/sh -c " .. transport.quote(script) })
  return argv
end

---@return string command The user runs this themselves, in their own terminal
function SSH:launch_hint(command)
  return ("ssh -t %s %s"):format(self.host, command)
end

function SSH:label()
  return self.host
end

---Fork a multiplexing master into the background. Every later call rides it, so it
---needs neither a TTY nor another authentication round.
function SSH:_master_argv(interactive)
  local argv = self:_base("yes")
  if not interactive then
    vim.list_extend(argv, { "-o", "BatchMode=yes" })
  end
  return vim.list_extend(argv, { "-N", "-f", self.host })
end

function SSH:_master_alive()
  local argv = self:_base("auto")
  vim.list_extend(argv, { "-O", "check", self.host })
  return transport.local_exec(argv).code == 0
end

---@param authenticate remote.Authenticate
function SSH:connect(authenticate)
  if self:_master_alive() or transport.local_exec(self:_master_argv(false)).code == 0 then
    return true
  end
  return authenticate(self:_master_argv(true), "Authenticate " .. self.host) == 0
end

return M
