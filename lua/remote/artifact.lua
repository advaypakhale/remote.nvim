local config = require("remote.config")
local layout = require("remote.layout")
local transport = require("remote.transport")

local M = {}

local OS = { Linux = "linux", Darwin = "macos" }
local ARCH = { x86_64 = "x86_64", amd64 = "x86_64", aarch64 = "arm64", arm64 = "arm64" }
local DOWNLOADERS = { wget = "wget -qO- %s", curl = "curl -fsSL %s" }

local q = transport.quote

function M.cache_dir()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "remote.nvim", "cache")
end

---@param target remote.Target
---@return string os, string arch Neovim release naming
function M.platform(target)
  local os_name, arch = OS[target.os], ARCH[target.arch]
  if os_name == nil then
    error(("unsupported target OS: %s"):format(target.os), 0)
  end
  if arch == nil then
    error(("unsupported target architecture: %s"):format(target.arch), 0)
  end
  return os_name, arch
end

---@return string
function M.nvim_version()
  local pinned = config.get().nvim_version
  if pinned then
    return pinned
  end

  local v = vim.version()
  -- Development builds have no matching release.
  if v.prerelease then
    return "stable"
  end
  return ("v%d.%d.%d"):format(v.major, v.minor, v.patch)
end

local function cache_key(url)
  return (url:gsub("^https?://", ""):gsub("[^%w%.%-]", "_"))
end

---@return string path Local cache entry, downloading it if absent
local function cached(url)
  local dest = vim.fs.joinpath(M.cache_dir(), cache_key(url))
  if vim.uv.fs_stat(dest) then
    return dest
  end

  vim.fn.mkdir(vim.fs.dirname(dest), "p")
  local part = dest .. ".part"
  if transport.local_exec({ "curl", "-fsSL", "-o", part, url }).code ~= 0 then
    vim.uv.fs_unlink(part)
    error(("download failed: %s"):format(url), 0)
  end

  local ok, err = vim.uv.fs_rename(part, dest)
  if not ok then
    error(("could not cache %s: %s"):format(url, err), 0)
  end
  return dest
end

---The target downloads for itself when it can, otherwise the bytes come from the
---local cache over the existing connection. Neither path stages a file on the target.
---@param steps { prepare: string, consume: string, finish: string? }
local function unpack(t, target, url, steps, what)
  local producer = DOWNLOADERS[target.downloader]
  local consume = producer and ("%s | %s"):format(producer:format(q(url)), steps.consume) or steps.consume
  local script = table.concat({ "set -e", steps.prepare, consume, steps.finish }, "\n")

  if producer then
    transport.check(t, script, what)
  else
    transport.pipe(t, { "cat", cached(url) }, script, what)
  end
end

---@param t remote.Transport
---@param target remote.Target
function M.install_nvim(t, target, prefix, version)
  local os_name, arch = M.platform(target)
  local url = ("https://github.com/neovim/neovim/releases/download/%s/nvim-%s-%s.tar.gz"):format(version, os_name, arch)
  local dest = q(layout.nvim(prefix, version))

  local root = q(vim.fs.dirname(layout.nvim(prefix, version)))

  unpack(t, target, url, {
    prepare = ("rm -rf %s\nmkdir -p %s"):format(dest, dest),
    consume = ("tar -xz -C %s --strip-components=1"):format(dest),
    -- Drop other versions only once this one has extracted.
    finish = ('for d in %s/*; do [ "$d" = %s ] || rm -rf "$d"; done'):format(root, dest),
  }, "install Neovim " .. version)
end

---@class remote.Tool
---@field url fun(os: string, arch: string): string
---@field bin string? Basename inside the archive; omit when the URL is the binary
---@field version string? Manifest key; defaults to the resolved URL

---@param spec remote.Tool
---@param target remote.Target
---@return string
function M.tool_version(spec, target)
  local version = spec.version or spec.url(M.platform(target))
  if type(version) ~= "string" then
    error("a tool needs a version, or a url function that returns a string", 0)
  end
  return version
end

---@param t remote.Transport
---@param target remote.Target
---@param spec remote.Tool
function M.install_tool(t, target, prefix, name, spec)
  local url = spec.url(M.platform(target))
  local dest = q(layout.bin(prefix, name))
  local bindir = q(vim.fs.dirname(layout.bin(prefix, name)))

  if not (vim.endswith(url, ".tar.gz") or vim.endswith(url, ".tgz")) then
    return unpack(t, target, url, {
      prepare = ("mkdir -p %s"):format(bindir),
      consume = ("cat > %s"):format(dest),
      finish = ("chmod u+x %s"):format(dest),
    }, "install " .. name)
  end

  local bin = spec.bin or name
  local scratch = q(layout.unpack(prefix, name))

  unpack(t, target, url, {
    prepare = ("rm -rf %s\nmkdir -p %s %s"):format(scratch, scratch, bindir),
    consume = ("tar -xz -C %s"):format(scratch),
    finish = table.concat({
      ("found=$(find %s -name %s -type f | head -n 1)"):format(scratch, q(bin)),
      ('[ -n "$found" ] || { echo %s >&2; exit 1; }'):format(q(bin .. " not found in archive")),
      ('cp "$found" %s'):format(dest),
      ("chmod u+x %s"):format(dest),
      ("rm -rf %s"):format(scratch),
    }, "\n"),
  }, "install " .. name)
end

return M
