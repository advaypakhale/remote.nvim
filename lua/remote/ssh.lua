-- SSH config parser for remote.nvim
-- Simplified parser that extracts Host entries with basic details

local M = {}

---Check if hostname contains wildcards
---@param host_name string
---@return boolean
local function hostname_contains_wildcard(host_name)
  return host_name:find("[*?!]") ~= nil
end

---Process a single line from SSH config
---@param raw_line string|nil
---@return string|nil directive
---@return string|nil directive_value
local function process_line(raw_line)
  if not raw_line then
    return nil, nil
  end

  -- Remove comments
  local comment_idx = raw_line:find("#", 1, true)
  if comment_idx then
    raw_line = raw_line:sub(1, comment_idx - 1)
  end

  -- Split and extract directive
  local line_parts = vim.split(raw_line, "%s+", { trimempty = true })
  if #line_parts > 1 then
    local directive = line_parts[1]
    local directive_value = table.concat(line_parts, " ", 2, #line_parts)
    return directive, directive_value
  end

  return nil, nil
end

---Parse a single SSH config file
---@param file_path string
---@return table[] hosts List of host entries
local function parse_file(file_path)
  file_path = vim.fn.expand(file_path)

  -- Check if file exists
  if vim.fn.filereadable(file_path) == 0 then
    return {}
  end

  local hosts = {}
  local current_host = nil

  for line in io.lines(file_path) do
    local directive, value = process_line(line)

    if directive == "Host" then
      -- Save previous host if it exists and is valid
      if current_host and not hostname_contains_wildcard(current_host.host) then
        table.insert(hosts, current_host)
      end

      -- Start new host entry (handle multiple hosts in one line)
      local host_names = vim.split(value, "%s+")
      if #host_names > 0 and not hostname_contains_wildcard(host_names[1]) then
        current_host = {
          host = host_names[1],
          hostname = nil,
          user = nil,
        }
      else
        current_host = nil
      end
    elseif directive == "HostName" and current_host then
      current_host.hostname = value
    elseif directive == "User" and current_host then
      current_host.user = value
    elseif directive == "Match" then
      -- Save current host and skip Match blocks
      if current_host and not hostname_contains_wildcard(current_host.host) then
        table.insert(hosts, current_host)
      end
      current_host = nil
    elseif directive == "Include" then
      -- Recursively parse included files
      local included_hosts = M.parse_ssh_config({ value })
      vim.list_extend(hosts, included_hosts)
    end
  end

  -- Don't forget the last host
  if current_host and not hostname_contains_wildcard(current_host.host) then
    table.insert(hosts, current_host)
  end

  return hosts
end

---Parse SSH config files and extract host entries
---@param config_paths string[] List of SSH config file paths
---@return table[] hosts List of host entries with format: { host, hostname, user }
function M.parse_ssh_config(config_paths)
  local all_hosts = {}
  local seen_hosts = {}

  for _, config_path in ipairs(config_paths) do
    local hosts = parse_file(config_path)

    -- Deduplicate hosts (first occurrence wins)
    for _, host in ipairs(hosts) do
      if not seen_hosts[host.host] then
        seen_hosts[host.host] = true
        table.insert(all_hosts, host)
      end
    end
  end

  return all_hosts
end

---Format host entry for display in picker
---@param host table Host entry
---@return string display_text
function M.format_host_for_display(host)
  local parts = { host.host }

  if host.user and host.hostname then
    table.insert(parts, string.format("(%s@%s)", host.user, host.hostname))
  elseif host.hostname then
    table.insert(parts, string.format("(%s)", host.hostname))
  elseif host.user then
    table.insert(parts, string.format("(%s@...)", host.user))
  end

  return table.concat(parts, " ")
end

return M
