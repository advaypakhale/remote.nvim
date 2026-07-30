---@class remote.Config
---@field ssh_config_path? string|string[]
---@field config_dir? string Config tree to copy; defaults to `stdpath("config")`
---@field prefix? string Install root on the target
---@field app_name? string NVIM_APPNAME on the target
---@field nvim_version? string Defaults to the local Neovim's version
---@field exclude? string[] Patterns excluded from the config tree
---@field copy_dirs? table<"data"|"state"|"cache", string[]>
---@field tools? table<string, remote.Tool>

local M = {}

---@type remote.Config
local defaults = {
  ssh_config_path = { "~/.ssh/config" },
  prefix = "~/.remote-nvim",
  app_name = "nvim",
  exclude = { ".git" },
  copy_dirs = {},
  tools = {},
}

---The single source of truth for what options exist and what they accept.
local OPTIONS = {
  ssh_config_path = { types = { "string", "table" } },
  config_dir = { types = "string", optional = true },
  prefix = { types = "string" },
  app_name = { types = "string" },
  nvim_version = { types = "string", optional = true },
  exclude = { types = "table" },
  copy_dirs = { types = "table" },
  tools = { types = "table" },
}

local COPY_DIR_KINDS = { "data", "state", "cache" }

---@type remote.Config?
local override

---@param opts remote.Config?
function M.setup(opts)
  override = opts
end

local function validate(cfg)
  for key, value in pairs(cfg) do
    local option = OPTIONS[key]
    if option == nil then
      error(("remote.nvim: unknown option '%s'"):format(key), 0)
    end
    vim.validate(key, value, option.types, option.optional)
  end

  for name, spec in pairs(cfg.tools) do
    vim.validate("tools." .. name, spec, "table")
    vim.validate(("tools.%s.url"):format(name), spec.url, "callable")
    vim.validate(("tools.%s.bin"):format(name), spec.bin, "string", true)
    vim.validate(("tools.%s.version"):format(name), spec.version, "string", true)
  end

  for kind, dirs in pairs(cfg.copy_dirs) do
    if not vim.tbl_contains(COPY_DIR_KINDS, kind) then
      error(("remote.nvim: copy_dirs key must be data, state or cache (got '%s')"):format(kind), 0)
    end
    vim.validate("copy_dirs." .. kind, dirs, "table")

    for _, dir in ipairs(dirs) do
      -- These become paths on the target, so they must stay inside the prefix.
      if dir:find("..", 1, true) or dir:sub(1, 1) == "/" then
        error(("remote.nvim: copy_dirs entry must be a relative subdirectory (got '%s')"):format(dir), 0)
      end
    end
  end
end

---@return remote.Config
function M.get()
  local cfg = vim.tbl_extend("force", vim.deepcopy(defaults), override or {})
  validate(cfg)

  if type(cfg.ssh_config_path) == "string" then
    cfg.ssh_config_path = { cfg.ssh_config_path }
  end
  return cfg
end

---@param home string Target's `$HOME`, resolving a leading `~`
---@return string
function M.prefix(home)
  local prefix = M.get().prefix
  local rest = prefix:match("^~/?(.*)$")
  if rest == nil then
    return prefix
  end
  return rest == "" and home or (home .. "/" .. rest)
end

return M
