local artifact = require("remote.artifact")
local config = require("remote.config")
local layout = require("remote.layout")
local target_mod = require("remote.target")
local transport = require("remote.transport")
local ui = require("remote.ui")

local M = {}

local q = transport.quote

---The target-side launcher. POSIX `sh`, which the target may not have bash for.
---@param tool_names string[]
---@return string
local function launcher(prefix, version, app_name, tool_names)
  local lines = { "#!/bin/sh" }

  for _, kind in ipairs(layout.XDG) do
    table.insert(lines, ("export XDG_%s_HOME=%s"):format(kind:upper(), q(layout.xdg(prefix, kind))))
  end
  table.insert(lines, ("export NVIM_APPNAME=%s"):format(q(app_name)))

  table.insert(lines, "")
  table.insert(lines, ("TOOLS=%s"):format(q(layout.tools(prefix))))
  table.insert(lines, 'mkdir -p "$TOOLS"')

  for _, name in ipairs(tool_names) do
    local bin = q(layout.bin(prefix, name))
    table.insert(
      lines,
      ('if ! command -v %s >/dev/null 2>&1 && [ -f %s ]; then ln -sf %s "$TOOLS/%s"; fi'):format(
        q(name),
        bin,
        bin,
        name
      )
    )
  end
  table.insert(lines, 'export PATH="$TOOLS:$PATH"')

  table.insert(lines, "")
  table.insert(lines, ('exec %s "$@"'):format(q(layout.nvim_binary(prefix, version))))

  return table.concat(lines, "\n") .. "\n"
end

local function local_config_dir()
  local dir = vim.fn.stdpath("config")
  if vim.fn.isdirectory(dir) == 0 then
    error(("local config directory does not exist: %s"):format(dir), 0)
  end
  return dir
end

---@return table[] Each entry is compared against the manifest before installing
local function artifacts(t, target, prefix, cfg, tool_names, version)
  local planned = {
    {
      key = "nvim_version",
      label = "Neovim " .. version,
      version = version,
      install = function()
        artifact.install_nvim(t, target, prefix, version)
      end,
    },
  }

  for _, name in ipairs(tool_names) do
    local spec = cfg.tools[name]
    table.insert(planned, {
      key = "tool_" .. name,
      label = name,
      version = artifact.tool_version(spec, target),
      install = function()
        artifact.install_tool(t, target, prefix, name, spec)
      end,
    })
  end

  return planned
end

---Idempotent, and free of UI so it can be driven headlessly.
---@param t remote.Transport
---@param progress remote.Progress
---@param force boolean? Reinstall binaries even when the manifest matches
---@return string prefix
function M.provision(t, progress, force)
  local cfg = config.get()
  local source = local_config_dir()

  progress:step("Probing " .. t:label())
  local target = target_mod.probe(t)
  if target.libc == "musl" then
    error("musl target unsupported: Neovim publishes no musl build", 0)
  end

  local prefix = config.prefix(target.home)
  local version = artifact.nvim_version()
  local manifest = target_mod.read_manifest(t, prefix)
  local desired = { os = target.os, arch = target.arch }

  local tool_names = vim.tbl_keys(cfg.tools)
  table.sort(tool_names)

  for _, item in ipairs(artifacts(t, target, prefix, cfg, tool_names, version)) do
    desired[item.key] = item.version
    if force or manifest[item.key] ~= item.version then
      progress:step("Installing " .. item.label)
      item.install()
    else
      progress:skip(item.label)
    end
  end

  progress:step("Copying config")
  transport.push_dir(t, source, layout.app(prefix, "config", cfg.app_name), { exclude = cfg.exclude })

  local uname = vim.uv.os_uname()
  if not vim.tbl_isempty(cfg.copy_dirs) and (uname.sysname ~= target.os or uname.machine ~= target.arch) then
    progress:warn(
      ("%s/%s → %s/%s: compiled artifacts in copy_dirs may not run"):format(
        uname.sysname,
        uname.machine,
        target.os,
        target.arch
      )
    )
  end

  for _, kind in ipairs({ "data", "state", "cache" }) do
    for _, subdir in ipairs(cfg.copy_dirs[kind] or {}) do
      progress:step(("Copying %s/%s"):format(kind, subdir))
      transport.push_dir(
        t,
        vim.fs.joinpath(vim.fn.stdpath(kind), subdir),
        ("%s/%s"):format(layout.app(prefix, kind, cfg.app_name), subdir)
      )
    end
  end

  progress:step("Installing launcher")
  transport.push_file(t, launcher(prefix, version, cfg.app_name, tool_names), layout.launcher(prefix), "755")
  target_mod.write_manifest(t, prefix, desired)

  return prefix
end

local function in_coroutine(fn)
  coroutine.wrap(function()
    local ok, err = pcall(fn)
    if not ok then
      vim.notify("remote.nvim: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)()
end

---@param t remote.Transport
local function connect(t)
  if not t:connect(ui.terminal) then
    error("could not connect to " .. t:label(), 0)
  end
end

---@param t remote.Transport
function M.run(t, force)
  in_coroutine(function()
    connect(t)

    local progress = ui.progress("remote.nvim → " .. t:label())
    local ok, result = pcall(M.provision, t, progress, force)
    if not ok then
      progress:fail(tostring(result))
      return
    end

    progress:info("")
    progress:info("Start Neovim on " .. t:label() .. " with:")
    progress:info("  " .. t:launch_hint(q(layout.launcher(result))))
  end)
end

---@param t remote.Transport
function M.cleanup(t)
  in_coroutine(function()
    connect(t)

    local prefix = config.prefix(target_mod.probe(t).home)
    transport.check(t, ("rm -rf %s"):format(q(prefix)), "remove " .. prefix)
    vim.notify(("remote.nvim: removed %s from %s"):format(prefix, t:label()))
  end)
end

return M
