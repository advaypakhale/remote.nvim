---Transports expose one primitive: argv that runs a POSIX `sh` script on the target.
---Everything else here is built on top of it.
---@class remote.Transport
---@field argv fun(self, script: string, opts?: { tty?: boolean }): string[]
---@field label fun(self): string
---@field connect fun(self, authenticate: remote.Authenticate): boolean

---Shows argv in a terminal and returns its exit code. Transports that need a TTY to
---authenticate call this; the rest ignore it.
---@alias remote.Authenticate fun(argv: string[], title: string): integer?

local M = {}

local is_macos = vim.uv.os_uname().sysname == "Darwin"

---`pipefail` is what surfaces a producer's failure; plain `sh` reports only the
---consumer's status.
local PIPELINE_SHELL = vim.fn.executable("bash") == 1 and { "bash", "-o", "pipefail", "-c" } or { "sh", "-c" }

---@param s string
---@return string POSIX single-quoted
function M.quote(s)
  return "'" .. s:gsub("'", [['\'']]) .. "'"
end

---@param argv string[]
---@return string A shell word list
function M.join(argv)
  return table.concat(vim.tbl_map(M.quote, argv), " ")
end

---Yields inside a coroutine and blocks otherwise, so the same call serves both the
---plugin's coroutine and a headless script.
local function await(argv, opts)
  local co = coroutine.running()
  if co == nil then
    return vim.system(argv, opts):wait()
  end
  vim.system(argv, opts, function(completed)
    vim.schedule(function()
      coroutine.resume(co, completed)
    end)
  end)
  return coroutine.yield()
end

---@class remote.Result
---@field code integer
---@field stdout string
---@field stderr string

local function result(r)
  return { code = r.code, stdout = r.stdout or "", stderr = r.stderr or "" }
end

local function raise(what, r)
  local detail = vim.trim(r.stderr ~= "" and r.stderr or r.stdout)
  error(("%s failed (exit %d)%s"):format(what, r.code, detail ~= "" and ": " .. detail or ""), 0)
end

---@return remote.Result
function M.local_exec(argv)
  return result(await(argv, { text = true }))
end

---@param t remote.Transport
---@param opts? { stdin?: string }
---@return remote.Result
function M.exec(t, script, opts)
  return result(await(t:argv(script), { stdin = opts and opts.stdin, text = true }))
end

---@param t remote.Transport
---@param what string Used in the error message
---@return remote.Result
function M.check(t, script, what, opts)
  local r = M.exec(t, script, opts)
  if r.code ~= 0 then
    raise(what, r)
  end
  return r
end

---Streams, so a large payload never sits in memory.
---@param t remote.Transport
---@param producer string[] Local command whose stdout feeds the target
function M.pipe(t, producer, script, what)
  local command = M.join(producer) .. " | " .. M.join(t:argv(script))
  local argv = vim.list_extend(vim.list_slice(PIPELINE_SHELL), { command })

  local r = result(await(argv, { text = true }))
  if r.code ~= 0 then
    raise(what, r)
  end
end

---Default reachability check, expressed through the primitive so no transport
---needs its own.
M.defaults = {
  connect = function(self)
    return M.exec(self, "true").code == 0
  end,
}

---Replace `dst` on the target with the contents of `src`.
---The remote `tar` uses no GNU-only options because it may be busybox.
---@param t remote.Transport
---@param opts? { exclude?: string[] }
function M.push_dir(t, src, dst, opts)
  if vim.fn.isdirectory(src) == 0 then
    error(("not a directory: %s"):format(src), 0)
  end

  local tar = { "tar", "-c", "-z", "-f", "-", "--no-xattrs", "--no-acls", "--numeric-owner" }
  if is_macos then
    table.insert(tar, "--disable-copyfile")
  end
  for _, pattern in ipairs(opts and opts.exclude or {}) do
    table.insert(tar, "--exclude=" .. pattern)
  end
  vim.list_extend(tar, { "-C", src, "." })

  local q = M.quote(dst)
  M.pipe(
    t,
    tar,
    ("rm -rf %s && mkdir -p %s && tar -x -z -f - -C %s && chown -R $(id -un) %s"):format(q, q, q, q),
    "copy " .. src
  )
end

---@param t remote.Transport
function M.push_file(t, content, dst, mode)
  local q = M.quote(dst)
  M.check(
    t,
    ("mkdir -p %s && cat > %s && chmod %s %s"):format(M.quote(vim.fs.dirname(dst)), q, mode, q),
    "write " .. dst,
    { stdin = content }
  )
end

return M
