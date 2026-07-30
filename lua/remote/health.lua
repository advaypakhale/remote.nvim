local M = {}

---`version` is nil where the binary has no useful version output.
local REQUIRED = {
  { name = "ssh", version = { "ssh", "-V" } },
  { name = "tar", version = { "tar", "--version" } },
  { name = "curl", version = { "curl", "--version" } },
  { name = "sh" },
}

local function report(spec)
  if vim.fn.executable(spec.name) == 0 then
    vim.health.error(("`%s` not found"):format(spec.name))
    return
  end
  if spec.version == nil then
    vim.health.ok(("%s: present"):format(spec.name))
    return
  end

  local result = require("remote.transport").local_exec(spec.version)
  local output = vim.trim(result.stdout .. result.stderr)
  vim.health.ok(("%s: %s"):format(spec.name, vim.split(output, "\n")[1]))
end

function M.check()
  vim.health.start("remote.nvim")

  for _, spec in ipairs(REQUIRED) do
    report(spec)
  end

  local ok, err = pcall(require("remote.config").get)
  if not ok then
    vim.health.error(tostring(err))
    return
  end
  vim.health.ok("configuration is valid")

  local artifact = require("remote.artifact")
  vim.health.info("binary cache: " .. artifact.cache_dir())
  vim.health.info("Neovim version for targets: " .. artifact.nvim_version())

  if vim.fn.executable("docker") == 0 then
    vim.health.warn("`docker` not found; container targets unavailable")
  else
    vim.health.ok("docker available")
  end
end

return M
