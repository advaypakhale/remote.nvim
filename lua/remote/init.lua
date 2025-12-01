-- Main module for remote.nvim

local M = {}

local config = require("remote.config")
local ssh = require("remote.ssh")
local ui = require("remote.ui")

---Setup function to configure the plugin
---@param opts table|nil User configuration options
function M.setup(opts)
  config.setup(opts)
end

---Execute remote command with given action and arguments
---@param action string Command action (setup, sync, cleanup)
---@param args string Raw argument string
local function execute_remote_command(action, args)
  local script_path = config.get_script_path()

  -- Check if script exists
  if vim.fn.filereadable(script_path) == 0 then
    vim.notify("remote-nvim.sh script not found at: " .. script_path, vim.log.levels.ERROR)
    return
  end

  local command = string.format("%s %s %s", script_path, action, args)
  ui.run_in_float(command)
end

---Show host picker and execute action
---@param action string Command action (setup, sync, cleanup)
local function pick_and_execute(action)
  -- Ensure config is initialized
  if not config.options.ssh_config_path then
    config.setup()
  end

  -- Parse SSH config
  local hosts = ssh.parse_ssh_config(config.options.ssh_config_path)

  if #hosts == 0 then
    vim.notify("No hosts found in SSH config", vim.log.levels.WARN)
    return
  end

  -- Prepare picker items
  local items = {}
  local host_map = {}

  for _, host in ipairs(hosts) do
    local display = ssh.format_host_for_display(host)
    table.insert(items, display)
    host_map[display] = host.host
  end

  -- Show picker
  vim.ui.select(items, {
    prompt = string.format("Select host for %s:", action),
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if choice then
      local hostname = host_map[choice]
      execute_remote_command(action, hostname)
    end
  end)
end

---Handle RemoteSetup command
---@param args string Command arguments
function M.setup_command(args)
  if args == "" then
    pick_and_execute("setup")
  else
    execute_remote_command("setup", args)
  end
end

---Handle RemoteSync command
---@param args string Command arguments
function M.sync_command(args)
  if args == "" then
    pick_and_execute("sync")
  else
    execute_remote_command("sync", args)
  end
end

---Handle RemoteCleanup command
---@param args string Command arguments
function M.cleanup_command(args)
  if args == "" then
    pick_and_execute("cleanup")
  else
    execute_remote_command("cleanup", args)
  end
end

return M
