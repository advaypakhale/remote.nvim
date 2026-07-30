---Paths under the install prefix on the target.
local M = {}

M.XDG = { "config", "data", "state", "cache" }

function M.xdg(prefix, kind)
  return ("%s/%s"):format(prefix, kind)
end

---e.g. `<prefix>/data/nvim`
function M.app(prefix, kind, app_name)
  return ("%s/%s/%s"):format(prefix, kind, app_name)
end

---Version-keyed so switching versions cannot leave a half-matched install.
function M.nvim(prefix, version)
  return ("%s/nvim/%s"):format(prefix, version)
end

function M.nvim_binary(prefix, version)
  return M.nvim(prefix, version) .. "/bin/nvim"
end

function M.bin(prefix, name)
  return ("%s/bin/%s"):format(prefix, name)
end

function M.tools(prefix)
  return prefix .. "/tools"
end

function M.launcher(prefix)
  return prefix .. "/rnvim"
end

function M.manifest(prefix)
  return prefix .. "/manifest"
end

---Scratch directory for unpacking an archive, removed by the script that uses it.
function M.unpack(prefix, name)
  return ("%s/.unpack-%s"):format(prefix, name)
end

return M
