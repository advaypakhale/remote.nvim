local M = {}

local MARKS = { active = "▸", done = "✓", skip = "·", warn = "!", fail = "✗", info = " " }

local function float(title, height)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.min(90, vim.o.columns - 4)
  height = math.min(height, vim.o.lines - 4)

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
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })

  return buf, win
end

local function close(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

---Run argv in a floating terminal so it can prompt, closing it on success. Must be
---called from a coroutine; it yields until the job exits.
---@param argv string[]
---@return integer code
function M.terminal(argv, title)
  local co = assert(coroutine.running(), "ui.terminal requires a coroutine")
  local _, win = float(title, 12)

  vim.fn.jobstart(argv, {
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          close(win)
        end
        coroutine.resume(co, code)
      end)
    end,
  })
  vim.cmd.startinsert()

  return coroutine.yield()
end

---@class remote.Progress
local Progress = {}
Progress.__index = Progress

---@return remote.Progress
function M.progress(title)
  local buf, win = float(title, 14)
  return setmetatable({ buf = buf, win = win, entries = {} }, Progress)
end

function Progress:_render()
  if not vim.api.nvim_buf_is_valid(self.buf) then
    return
  end

  local lines = vim.tbl_map(function(entry)
    return (" %s %s"):format(MARKS[entry.state], entry.text)
  end, self.entries)

  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.bo[self.buf].modifiable = false
  if vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_set_cursor(self.win, { #lines, 0 })
  end
end

function Progress:_settle(state)
  local last = self.entries[#self.entries]
  if last and last.state == "active" then
    last.state = state
  end
end

function Progress:_push(state, text)
  self:_settle("done")
  table.insert(self.entries, { state = state, text = text })
  self:_render()
end

function Progress:step(text)
  self:_push("active", text)
end

function Progress:skip(text)
  self:_push("skip", text)
end

function Progress:warn(text)
  self:_push("warn", text)
end

function Progress:info(text)
  self:_push("info", text)
end

function Progress:fail(text)
  self:_settle("fail")
  for _, line in ipairs(vim.split(text, "\n", { trimempty = true })) do
    table.insert(self.entries, { state = "fail", text = line })
  end
  self:_render()
end

function Progress:close()
  close(self.win)
end

return M
