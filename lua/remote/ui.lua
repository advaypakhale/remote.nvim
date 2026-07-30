local M = {}

---Run argv in a floating terminal so it can prompt, closing it on success. Must be
---called from a coroutine; it yields until the job exits.
---@param argv string[]
---@return integer code
function M.terminal(argv, title)
  local co = assert(coroutine.running(), "ui.terminal requires a coroutine")

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

return M
