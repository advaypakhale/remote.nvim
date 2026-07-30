local layout = require("remote.layout")
local q = require("remote.transport").quote

---Generates the target-side launcher. POSIX `sh`, since Alpine and busybox have no bash.
---@param tool_names string[]
---@return string
return function(prefix, version, app_name, tool_names)
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
