local M = {}

local MAX_DEPTH = 16

---@class remote.Host
---@field host string
---@field hostname string?
---@field user string?

local function has_wildcard(name)
  return name:find("[*?!]") ~= nil
end

---@return string? directive Lowercased
---@return string? value
local function directive(line)
  local key, value = line:gsub("#.*", ""):match("^%s*([%w_]+)[%s=]+(.-)%s*$")
  if key == nil or value == "" then
    return nil
  end
  return key:lower(), value
end

---`Include` paths are relative to `~/.ssh` per ssh_config(5), and may glob.
---`glob()` expands `~` itself; `expand()` must not be used here because it joins
---multiple matches with newlines.
local function include_paths(value)
  local found = {}
  for _, pattern in ipairs(vim.split(value, "%s+", { trimempty = true })) do
    if not pattern:match("^[~/]") then
      pattern = "~/.ssh/" .. pattern
    end
    vim.list_extend(found, vim.fn.glob(pattern, false, true))
  end
  return found
end

local function parse(path, hosts, seen, depth)
  path = vim.uv.fs_realpath(vim.fs.normalize(path))
  if path == nil or seen[path] or depth > MAX_DEPTH then
    return
  end
  seen[path] = true

  local stat = vim.uv.fs_stat(path)
  if stat == nil or stat.type ~= "file" then
    return
  end

  local current
  local function flush()
    if current and not has_wildcard(current.host) then
      table.insert(hosts, current)
    end
    current = nil
  end

  for line in io.lines(path) do
    local key, value = directive(line)
    if key == "host" then
      flush()
      local name = vim.split(value, "%s+", { trimempty = true })[1]
      if name and not has_wildcard(name) then
        current = { host = name }
      end
    elseif key == "match" then
      flush()
    elseif key == "include" then
      for _, included in ipairs(include_paths(value)) do
        parse(included, hosts, seen, depth + 1)
      end
    elseif current then
      if key == "hostname" then
        current.hostname = value
      elseif key == "user" then
        current.user = value
      end
    end
  end
  flush()
end

---@param paths string[]
---@return remote.Host[] Deduplicated by name, first occurrence wins
function M.hosts(paths)
  local all, seen_file, seen_host = {}, {}, {}

  for _, path in ipairs(paths) do
    parse(path, all, seen_file, 1)
  end

  return vim.tbl_filter(function(host)
    if seen_host[host.host] then
      return false
    end
    seen_host[host.host] = true
    return true
  end, all)
end

---@param host remote.Host
---@return string
function M.format(host)
  if host.user and host.hostname then
    return ("%s (%s@%s)"):format(host.host, host.user, host.hostname)
  elseif host.hostname then
    return ("%s (%s)"):format(host.host, host.hostname)
  elseif host.user then
    return ("%s (%s@…)"):format(host.host, host.user)
  end
  return host.host
end

return M
