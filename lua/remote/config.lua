-- Configuration module for remote.nvim

local M = {}

-- Default configuration
M.defaults = {
    ssh_config_path = "~/.ssh/config",
}

-- Current configuration
M.options = {}

-- Setup function
---@param opts table|nil User configuration
function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

    -- Normalize ssh_config_path to always be a table
    if type(M.options.ssh_config_path) == "string" then
        M.options.ssh_config_path = { M.options.ssh_config_path }
    end
end

-- Get script path (always in plugin directory)
function M.get_script_path()
    local plugin_dir =
        vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
    return vim.fn.fnamemodify(plugin_dir .. "/scripts/remote-nvim.sh", ":p")
end

return M
