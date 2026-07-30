local layout = require("remote.layout")
local transport = require("remote.transport")

local M = {}

local q = transport.quote

local PROBE = table.concat({
  "uname -sm",
  [[printf '%s\n' "$HOME"]],
  "if command -v wget >/dev/null 2>&1; then echo wget",
  "elif command -v curl >/dev/null 2>&1; then echo curl",
  "else echo none; fi",
  -- Cheaper than `ldd`, and present on busybox.
  "if ls /lib/ld-musl-* >/dev/null 2>&1; then echo musl; else echo glibc; fi",
}, "\n")

---@class remote.Target
---@field os string `uname -s`
---@field arch string `uname -m`
---@field home string
---@field downloader "wget"|"curl"|nil
---@field libc "musl"|"glibc"

---@param t remote.Transport
---@return remote.Target
function M.probe(t)
  local out = transport.check(t, PROBE, "probe " .. t:label()).stdout
  local lines = vim.split(vim.trim(out), "\n", { trimempty = true })
  if #lines < 4 then
    error("probe returned unexpected output:\n" .. out, 0)
  end

  local platform = vim.split(vim.trim(lines[1]), "%s+", { trimempty = true })
  local downloader = vim.trim(lines[3])

  return {
    os = platform[1],
    arch = platform[2],
    home = vim.trim(lines[2]),
    downloader = downloader ~= "none" and downloader or nil,
    libc = vim.trim(lines[4]),
  }
end

---@param t remote.Transport
---@return table<string, string>
function M.read_manifest(t, prefix)
  local path = q(layout.manifest(prefix))
  local r = transport.exec(t, ("cat %s 2>/dev/null || true"):format(path))

  local values = {}
  for _, line in ipairs(vim.split(r.stdout, "\n", { trimempty = true })) do
    local key, value = line:match("^([%w_]+)=(.*)$")
    if key then
      values[key] = value
    end
  end
  return values
end

---@param t remote.Transport
---@param values table<string, string>
function M.write_manifest(t, prefix, values)
  local keys = vim.tbl_keys(values)
  table.sort(keys)

  local lines = vim.tbl_map(function(key)
    return key .. "=" .. values[key]
  end, keys)

  transport.push_file(t, table.concat(lines, "\n") .. "\n", layout.manifest(prefix), "644")
end

return M
