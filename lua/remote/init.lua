-- remote.nvim — installs Neovim, your config, and declared tools into one
-- directory on an ssh host or a running container.
--
-- A transport runs POSIX `sh` scripts on a target. Provisioning probes the
-- target, diffs desired versions against the manifest from the previous run,
-- streams what is missing over the connection, and installs a launcher that
-- pins Neovim's environment to the install prefix.
--
-- The ssh config parser is in `remote/ssh_config.lua`.

local ssh_config = require("remote.ssh_config")

local M = {}

-- Configuration ---------------------------------------------------------------

---@class remote.Config
---@field ssh_config_path? string|string[]
---@field config_dir? string Config tree to copy; defaults to `stdpath("config")`
---@field prefix? string Install root on the target
---@field app_name? string NVIM_APPNAME on the target
---@field nvim_version? string Defaults to the local Neovim's version
---@field exclude? string[] Patterns excluded from the config tree
---@field copy_dirs? table<"data"|"state"|"cache", string[]>
---@field tools? table<string, remote.Tool>

local OPTIONS = {
  ssh_config_path = { types = { "string", "table" }, default = { "~/.ssh/config" } },
  config_dir = { types = "string" },
  prefix = { types = "string", default = "~/.remote-nvim" },
  app_name = { types = "string", default = "nvim" },
  nvim_version = { types = "string" },
  exclude = { types = "table", default = { ".git" } },
  copy_dirs = { types = "table", default = {} },
  tools = { types = "table", default = {} },
}

---@type remote.Config?
local override

---@return remote.Config
local function config()
  local cfg = {}
  for key, option in pairs(OPTIONS) do
    cfg[key] = vim.deepcopy(option.default)
  end

  for key, value in pairs(override or {}) do
    local option = OPTIONS[key]
    if option == nil then
      error(("remote.nvim: unknown option '%s'"):format(key), 0)
    end
    vim.validate(key, value, option.types)
    cfg[key] = value
  end

  for name, spec in pairs(cfg.tools) do
    vim.validate("tools." .. name, spec, "table")
    vim.validate(("tools.%s.url"):format(name), spec.url, "callable")
    vim.validate(("tools.%s.bin"):format(name), spec.bin, "string", true)
    vim.validate(("tools.%s.version"):format(name), spec.version, "string", true)
  end

  for kind, dirs in pairs(cfg.copy_dirs) do
    if kind ~= "data" and kind ~= "state" and kind ~= "cache" then
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

  if type(cfg.ssh_config_path) == "string" then
    cfg.ssh_config_path = { cfg.ssh_config_path }
  end
  return cfg
end

-- Processes -------------------------------------------------------------------

---@param s string
---@return string POSIX single-quoted
local function quote(s)
  return "'" .. s:gsub("'", [['\'']]) .. "'"
end

---@param argv string[]
---@return string A shell word list
local function join(argv)
  return table.concat(vim.tbl_map(quote, argv), " ")
end

---Yields inside a coroutine and blocks otherwise, so the same call serves both
---the plugin's coroutine and a headless script.
local function await(argv, opts)
  if vim.fn.executable(argv[1]) == 0 then
    error(("`%s` is not installed on your machine"):format(argv[1]), 0)
  end

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

---@return remote.Result
local function result(r)
  return { code = r.code, stdout = r.stdout or "", stderr = r.stderr or "" }
end

local function raise(what, r)
  local detail = vim.trim(r.stderr ~= "" and r.stderr or r.stdout)
  error(("%s failed (exit %d)%s"):format(what, r.code, detail ~= "" and ": " .. detail or ""), 0)
end

---@return remote.Result
local function local_exec(argv)
  return result(await(argv, { text = true }))
end

-- Transports ------------------------------------------------------------------

---A transport runs POSIX `sh` scripts on one target.
---@class remote.Transport
---@field label string Shown in prompts and error messages
---@field argv fun(script: string): string[] Local argument vector that runs `script` on the target
---@field connect fun(authenticate: remote.Authenticate): boolean
---@field launch_hint fun(command: string): string What the user runs in their own terminal

---Runs argv in a terminal and returns its exit code, for transports that need
---a TTY to authenticate.
---@alias remote.Authenticate fun(argv: string[], title: string): integer?

---@param t remote.Transport
---@param opts? { stdin?: string }
---@return remote.Result
local function exec(t, script, opts)
  return result(await(t.argv(script), { stdin = opts and opts.stdin, text = true }))
end

---@param what string Used in the error message
---@return remote.Result
local function check(t, script, what, opts)
  local r = exec(t, script, opts)
  if r.code ~= 0 then
    raise(what, r)
  end
  return r
end

---`pipefail` is what surfaces a producer's failure; plain `sh` reports only
---the consumer's status.
local PIPELINE_SHELL = vim.fn.executable("bash") == 1 and { "bash", "-o", "pipefail", "-c" } or { "sh", "-c" }

---Streams, so a large payload never sits in memory.
---@param t remote.Transport
---@param producer string[] Local command whose stdout feeds the target
local function pipe(t, producer, script, what)
  local command = join(producer) .. " | " .. join(t.argv(script))
  local r = result(await(vim.list_extend(vim.list_slice(PIPELINE_SHELL), { command }), { text = true }))
  if r.code ~= 0 then
    raise(what, r)
  end
end

---Replace `dst` on the target with the contents of `src`.
---The remote `tar` uses no GNU-only options because it may be busybox.
---@param t remote.Transport
---@param opts? { exclude?: string[] }
local function push_dir(t, src, dst, opts)
  if vim.fn.isdirectory(src) == 0 then
    error(("not a directory: %s"):format(src), 0)
  end

  local tar = { "tar", "-c", "-z", "-f", "-", "--no-xattrs", "--no-acls", "--numeric-owner" }
  if vim.uv.os_uname().sysname == "Darwin" then
    table.insert(tar, "--disable-copyfile")
  end
  for _, pattern in ipairs(opts and opts.exclude or {}) do
    table.insert(tar, "--exclude=" .. pattern)
  end
  vim.list_extend(tar, { "-C", src, "." })

  local q = quote(dst)
  pipe(
    t,
    tar,
    ("rm -rf %s && mkdir -p %s && tar -x -z -f - -C %s && chown -R $(id -un) %s"):format(q, q, q, q),
    "copy " .. src
  )
end

---@param t remote.Transport
local function push_file(t, content, dst, mode)
  local q = quote(dst)
  local script = ("mkdir -p %s && cat > %s && chmod %s %s"):format(quote(vim.fs.dirname(dst)), q, mode, q)
  check(t, script, "write " .. dst, { stdin = content })
end

---@param host string
---@param conn_opts string[]? Extra arguments passed through to `ssh`
---@return remote.Transport
local function ssh_transport(host, conn_opts)
  conn_opts = conn_opts or {}

  ---@param master "auto"|"yes"
  local function base(master)
    -- stylua: ignore
    local argv = {
      "ssh",
      "-o", "ControlMaster=" .. master,
      "-o", "ControlPath=/tmp/rnvim-%C",
      "-o", "ControlPersist=60",
      "-o", "ConnectTimeout=10",
    }
    return vim.list_extend(argv, conn_opts)
  end

  ---Fork a multiplexing master into the background. Every later call rides it,
  ---so authentication happens at most once.
  local function master_argv(interactive)
    local argv = base("yes")
    if not interactive then
      vim.list_extend(argv, { "-o", "BatchMode=yes" })
    end
    return vim.list_extend(argv, { "-N", "-f", host })
  end

  local t = { label = host }

  function t.argv(script)
    return vim.list_extend(base("auto"), { host, "/bin/sh -c " .. quote(script) })
  end

  function t.connect(authenticate)
    local alive = vim.list_extend(base("auto"), { "-O", "check", host })
    if local_exec(alive).code == 0 or local_exec(master_argv(false)).code == 0 then
      return true
    end
    return authenticate(master_argv(true), "Authenticate " .. host) == 0
  end

  function t.launch_hint(command)
    local argv = vim.list_extend({ "ssh", "-t" }, conn_opts)
    return table.concat(vim.list_extend(argv, { host, command }), " ")
  end

  return t
end

---@param container string Name or ID
---@return remote.Transport
local function docker_transport(container)
  local t = { label = container }

  function t.argv(script)
    return { "docker", "exec", "-i", container, "/bin/sh", "-c", script }
  end

  function t.connect()
    return exec(t, "true").code == 0
  end

  function t.launch_hint(command)
    return ("docker exec -it %s %s"):format(container, command)
  end

  return t
end

---@return string[] containers Running containers, empty when docker is unavailable
local function docker_containers()
  if vim.fn.executable("docker") == 0 then
    return {}
  end

  local r = local_exec({ "docker", "ps", "--format", "{{.Names}}" })
  if r.code ~= 0 then
    return {}
  end
  return vim.split(vim.trim(r.stdout), "\n", { trimempty = true })
end

---@param spec string An ssh host, or `docker:<container>`
---@param conn_opts string[]? Passed through to `ssh`
---@return remote.Transport
local function resolve(spec, conn_opts)
  local container = spec:match("^docker:(.+)$")
  if container then
    if conn_opts and #conn_opts > 0 then
      vim.notify("remote.nvim: extra arguments only apply to ssh targets", vim.log.levels.WARN)
    end
    return docker_transport(container)
  end
  return ssh_transport(spec, conn_opts)
end

-- The target ------------------------------------------------------------------

---@class remote.Target
---@field os string `uname -s`
---@field arch string `uname -m`
---@field home string
---@field downloader "wget"|"curl"|nil
---@field libc "musl"|"glibc"

local PROBE = table.concat({
  "uname -sm",
  [[printf '%s\n' "$HOME"]],
  "if command -v wget >/dev/null 2>&1; then echo wget",
  "elif command -v curl >/dev/null 2>&1; then echo curl",
  "else echo none; fi",
  -- Cheaper than `ldd`, and present on busybox.
  "if ls /lib/ld-musl-* >/dev/null 2>&1; then echo musl; else echo glibc; fi",
}, "\n")

---@param t remote.Transport
---@return remote.Target
local function probe(t)
  local out = check(t, PROBE, "probe " .. t.label).stdout
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

---What an earlier run installed, one `key=value` per line.
---@param t remote.Transport
---@return table<string, string>
local function read_manifest(t, prefix)
  local r = exec(t, ("cat %s 2>/dev/null || true"):format(quote(prefix .. "/manifest")))

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
local function write_manifest(t, prefix, values)
  local keys = vim.tbl_keys(values)
  table.sort(keys)

  local lines = vim.tbl_map(function(key)
    return key .. "=" .. values[key]
  end, keys)

  push_file(t, table.concat(lines, "\n") .. "\n", prefix .. "/manifest", "644")
end

-- Artifacts -------------------------------------------------------------------

local OS = { Linux = "linux", Darwin = "macos" }
local ARCH = { x86_64 = "x86_64", amd64 = "x86_64", aarch64 = "arm64", arm64 = "arm64" }
local DOWNLOADERS = { wget = "wget -qO- %s", curl = "curl -fsSL %s" }

---@param target remote.Target
---@return string os, string arch Release-asset naming
local function platform(target)
  local os_name, arch = OS[target.os], ARCH[target.arch]
  if os_name == nil then
    error(("unsupported target OS: %s"):format(target.os), 0)
  end
  if arch == nil then
    error(("unsupported target architecture: %s"):format(target.arch), 0)
  end
  return os_name, arch
end

---@return string The local Neovim's release, or `stable` for a development
---build, which has no matching release
local function local_nvim_version()
  local v = vim.version()
  if v.prerelease then
    return "stable"
  end
  return ("v%d.%d.%d"):format(v.major, v.minor, v.patch)
end

---@return string path A local copy of `url`, downloading it on first use
local function cached(url)
  local key = (url:gsub("^https?://", ""):gsub("[^%w%.%-]", "_"))
  local dest = vim.fs.joinpath(vim.fn.stdpath("data"), "remote.nvim", "cache", key)
  if vim.uv.fs_stat(dest) then
    return dest
  end

  vim.fn.mkdir(vim.fs.dirname(dest), "p")
  local part = dest .. ".part"
  if local_exec({ "curl", "-fsSL", "-o", part, url }).code ~= 0 then
    vim.uv.fs_unlink(part)
    error(("download failed: %s"):format(url), 0)
  end

  local ok, err = vim.uv.fs_rename(part, dest)
  if not ok then
    error(("could not cache %s: %s"):format(url, err), 0)
  end
  return dest
end

---The target downloads for itself when it can; otherwise the bytes come from
---the local cache over the existing connection. Neither path stages an archive
---on the target.
---@param steps { prepare: string, consume: string, finish: string? }
local function unpack(t, target, url, steps, what)
  local downloader = DOWNLOADERS[target.downloader]
  local consume = downloader and ("%s | %s"):format(downloader:format(quote(url)), steps.consume) or steps.consume
  local script = table.concat({ "set -e", steps.prepare, consume, steps.finish }, "\n")

  if downloader then
    check(t, script, what)
  else
    pipe(t, { "cat", cached(url) }, script, what)
  end
end

---Version-keyed, so switching versions cannot leave a half-matched install.
local function nvim_dir(prefix, version)
  return ("%s/nvim/%s"):format(prefix, version)
end

---@param t remote.Transport
---@param target remote.Target
local function install_nvim(t, target, prefix, version)
  local os_name, arch = platform(target)
  local url = ("https://github.com/neovim/neovim/releases/download/%s/nvim-%s-%s.tar.gz"):format(version, os_name, arch)
  local dest = quote(nvim_dir(prefix, version))

  unpack(t, target, url, {
    prepare = ("rm -rf %s\nmkdir -p %s"):format(dest, dest),
    consume = ("tar -xz -C %s --strip-components=1"):format(dest),
    -- Drop other versions only once this one has extracted.
    finish = ('for d in %s/*; do [ "$d" = %s ] || rm -rf "$d"; done'):format(quote(prefix .. "/nvim"), dest),
  }, "install Neovim " .. version)
end

---@class remote.Tool
---@field url fun(os: string, arch: string): string
---@field bin string? Basename inside the archive; omit when the URL is the binary
---@field version string? Manifest key; defaults to the resolved URL

---@param spec remote.Tool
---@param target remote.Target
---@return string
local function tool_version(spec, target)
  local version = spec.version or spec.url(platform(target))
  if type(version) ~= "string" then
    error("a tool needs a version, or a url function that returns a string", 0)
  end
  return version
end

local function tool_bin(prefix, name)
  return ("%s/bin/%s"):format(prefix, name)
end

---@param t remote.Transport
---@param target remote.Target
---@param spec remote.Tool
local function install_tool(t, target, prefix, name, spec)
  local url = spec.url(platform(target))
  local dest = quote(tool_bin(prefix, name))
  local bindir = quote(prefix .. "/bin")

  if not (vim.endswith(url, ".tar.gz") or vim.endswith(url, ".tgz")) then
    return unpack(t, target, url, {
      prepare = ("mkdir -p %s"):format(bindir),
      consume = ("cat > %s"):format(dest),
      finish = ("chmod u+x %s"):format(dest),
    }, "install " .. name)
  end

  local bin = spec.bin or name
  local scratch = quote(("%s/.unpack-%s"):format(prefix, name))

  unpack(t, target, url, {
    prepare = ("rm -rf %s\nmkdir -p %s %s"):format(scratch, scratch, bindir),
    consume = ("tar -xz -C %s"):format(scratch),
    finish = table.concat({
      ("found=$(find %s -name %s -type f | head -n 1)"):format(scratch, quote(bin)),
      ('[ -n "$found" ] || { echo %s >&2; exit 1; }'):format(quote(bin .. " not found in archive")),
      ('cp "$found" %s'):format(dest),
      ("chmod u+x %s"):format(dest),
      ("rm -rf %s"):format(scratch),
    }, "\n"),
  }, "install " .. name)
end

-- Provisioning ----------------------------------------------------------------

local XDG = { "config", "data", "state", "cache" }

local function launcher_path(prefix)
  return prefix .. "/rnvim"
end

---The target-side launcher: POSIX `sh`, because the target may not have bash.
---@param tool_names string[]
---@return string
local function launcher(prefix, version, app_name, tool_names)
  local lines = { "#!/bin/sh" }

  for _, kind in ipairs(XDG) do
    table.insert(lines, ("export XDG_%s_HOME=%s"):format(kind:upper(), quote(("%s/%s"):format(prefix, kind))))
  end
  table.insert(lines, ("export NVIM_APPNAME=%s"):format(quote(app_name)))

  table.insert(lines, "")
  table.insert(lines, ("TOOLS=%s"):format(quote(prefix .. "/tools")))
  -- Rebuilt every run, so a tool the target has gained since the last one
  -- stops being shadowed by our symlink.
  table.insert(lines, 'rm -rf "$TOOLS"')
  table.insert(lines, 'mkdir -p "$TOOLS"')

  for _, name in ipairs(tool_names) do
    local bin = quote(tool_bin(prefix, name))
    local link = ('if ! command -v %s >/dev/null 2>&1 && [ -f %s ]; then ln -sf %s "$TOOLS"/%s; fi'):format(
      quote(name),
      bin,
      bin,
      quote(name)
    )
    table.insert(lines, link)
  end
  table.insert(lines, 'export PATH="$TOOLS:$PATH"')

  table.insert(lines, "")
  table.insert(lines, ('exec %s "$@"'):format(quote(nvim_dir(prefix, version) .. "/bin/nvim")))

  return table.concat(lines, "\n") .. "\n"
end

---@return table[] plan Each entry is diffed against the manifest before installing
local function artifacts(t, target, prefix, cfg, tool_names, version)
  local plan = {
    {
      key = "nvim_version",
      label = "Neovim " .. version,
      version = version,
      install = function()
        install_nvim(t, target, prefix, version)
      end,
    },
  }

  for _, name in ipairs(tool_names) do
    local spec = cfg.tools[name]
    table.insert(plan, {
      key = "tool_" .. name,
      label = name,
      version = tool_version(spec, target),
      install = function()
        install_tool(t, target, prefix, name, spec)
      end,
    })
  end

  return plan
end

---@param home string The target's `$HOME`, resolving a leading `~`
local function expand_prefix(prefix, home)
  local rest = prefix:match("^~/?(.*)$")
  if rest == nil then
    return prefix
  end
  return rest == "" and home or home .. "/" .. rest
end

local function local_config_dir(cfg)
  local dir = vim.fs.normalize(cfg.config_dir or vim.fn.stdpath("config"))
  if vim.fn.isdirectory(dir) == 0 then
    error(("config directory does not exist: %s"):format(dir), 0)
  end
  return dir
end

---Idempotent, and free of UI so it can be driven headlessly.
---@param t remote.Transport
---@param report fun(message: string, level?: integer)
---@param force boolean? Reinstall binaries even when the manifest matches
---@return string prefix The install directory on the target
local function provision(t, report, force)
  local cfg = config()
  local source = local_config_dir(cfg)

  report("probing " .. t.label)
  local target = probe(t)
  if target.libc == "musl" then
    error("musl target unsupported: Neovim publishes no musl build", 0)
  end

  local prefix = expand_prefix(cfg.prefix, target.home)
  local version = cfg.nvim_version or local_nvim_version()
  local manifest = read_manifest(t, prefix)
  local desired = { os = target.os, arch = target.arch }

  local tool_names = vim.tbl_keys(cfg.tools)
  table.sort(tool_names)

  for _, item in ipairs(artifacts(t, target, prefix, cfg, tool_names, version)) do
    desired[item.key] = item.version
    if force or manifest[item.key] ~= item.version then
      report("installing " .. item.label)
      item.install()
    else
      report(item.label .. " is already installed")
    end
  end

  local function app_dir(kind)
    return ("%s/%s/%s"):format(prefix, kind, cfg.app_name)
  end

  report("copying config")
  push_dir(t, source, app_dir("config"), { exclude = cfg.exclude })

  local uname = vim.uv.os_uname()
  if not vim.tbl_isempty(cfg.copy_dirs) and (uname.sysname ~= target.os or uname.machine ~= target.arch) then
    report(
      ("%s/%s → %s/%s: compiled artifacts in copy_dirs may not run"):format(
        uname.sysname,
        uname.machine,
        target.os,
        target.arch
      ),
      vim.log.levels.WARN
    )
  end

  for _, kind in ipairs({ "data", "state", "cache" }) do
    for _, subdir in ipairs(cfg.copy_dirs[kind] or {}) do
      report(("copying %s/%s"):format(kind, subdir))
      push_dir(t, vim.fs.joinpath(vim.fn.stdpath(kind), subdir), app_dir(kind) .. "/" .. subdir)
    end
  end

  report("installing launcher")
  push_file(t, launcher(prefix, version, cfg.app_name, tool_names), launcher_path(prefix), "755")
  write_manifest(t, prefix, desired)

  return prefix
end

-- Discovery -------------------------------------------------------------------

local discovered = { specs = nil, labels = nil, at = 0 }

---Scanning the ssh config and listing containers is too slow to repeat per
---keystroke, and completion calls this on every one.
local function discover()
  local now = vim.uv.now()
  if discovered.specs and now - discovered.at < 2000 then
    return discovered.specs, discovered.labels
  end

  local specs, labels = {}, {}
  for _, host in ipairs(ssh_config.hosts(config().ssh_config_path)) do
    table.insert(specs, host.host)
    labels[host.host] = ssh_config.format(host)
  end
  for _, container in ipairs(docker_containers()) do
    local spec = "docker:" .. container
    table.insert(specs, spec)
    labels[spec] = spec
  end

  discovered = { specs = specs, labels = labels, at = now }
  return specs, labels
end

---@param fn fun(spec: string)
local function pick(prompt, fn)
  local specs, labels = discover()
  if #specs == 0 then
    vim.notify("remote.nvim: no hosts in ssh config and no running containers", vim.log.levels.WARN)
    return
  end

  vim.ui.select(specs, {
    prompt = prompt,
    format_item = function(spec)
      return labels[spec]
    end,
  }, function(choice)
    if choice then
      fn(choice)
    end
  end)
end

-- Public API ------------------------------------------------------------------

---Run argv in a floating terminal so it can prompt, closing it on success.
---Must be called from a coroutine; it yields until the job exits.
---@param argv string[]
---@param title string
---@return integer code
local function terminal(argv, title)
  local co = assert(coroutine.running(), "terminal requires a coroutine")

  local buf = vim.api.nvim_create_buf(false, true)
  local width, height = math.min(90, vim.o.columns - 4), math.min(12, vim.o.lines - 4)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })
  vim.bo[buf].bufhidden = "wipe"

  vim.fn.jobstart(argv, {
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        coroutine.resume(co, code)
      end)
    end,
  })
  vim.cmd.startinsert()

  return coroutine.yield()
end

local function notify(message, level)
  vim.notify("remote.nvim: " .. message, level or vim.log.levels.INFO)
end

local function in_coroutine(fn)
  coroutine.wrap(function()
    local ok, err = pcall(fn)
    if not ok then
      notify(tostring(err), vim.log.levels.ERROR)
    end
  end)()
end

---@param t remote.Transport
local function connect(t)
  if not t.connect(terminal) then
    error("could not connect to " .. t.label, 0)
  end
end

---@param opts remote.Config?
function M.setup(opts)
  override = opts
end

---@return string[] specs Completion candidates
function M.targets()
  return (discover())
end

---Provision without a UI, for `nvim -l` scripts.
---@param spec string An ssh host, or `docker:<container>`
---@param report fun(message: string, level?: integer)? Defaults to `vim.notify`
---@param force boolean?
---@return string prefix
function M.provision(spec, report, force)
  return provision(resolve(spec), report or notify, force)
end

---@param spec string? Prompts when omitted
---@param conn_opts string[]?
---@param force boolean? Reinstall binaries even if the manifest matches
function M.install(spec, conn_opts, force)
  if spec == nil then
    return pick("Install Neovim on:", function(chosen)
      M.install(chosen, conn_opts, force)
    end)
  end

  local t = resolve(spec, conn_opts)
  in_coroutine(function()
    connect(t)
    local prefix = provision(t, notify, force)
    notify(("start Neovim on %s with:\n%s"):format(t.label, t.launch_hint(quote(launcher_path(prefix)))))
  end)
end

---@param spec string? Prompts when omitted
function M.cleanup(spec)
  if spec == nil then
    return pick("Remove remote.nvim from:", M.cleanup)
  end
  if vim.fn.confirm(("Remove %s from %s?"):format(config().prefix, spec), "&Yes\n&No", 2) ~= 1 then
    return
  end

  local t = resolve(spec)
  in_coroutine(function()
    connect(t)
    local prefix = expand_prefix(config().prefix, probe(t).home)
    check(t, ("rm -rf %s"):format(quote(prefix)), "remove " .. prefix)
    notify(("removed %s from %s"):format(prefix, t.label))
  end)
end

return M
