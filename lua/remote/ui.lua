-- UI module for remote.nvim
-- Handles floating terminal display

local M = {}

---Run command in a floating terminal
---@param command string Full command to execute
function M.run_in_float(command)
  -- Create scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  -- Calculate window size (80% of screen)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Open floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })

  -- Run command in terminal
  vim.fn.termopen(command, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.notify("Remote operation completed successfully", vim.log.levels.INFO)
      else
        vim.notify("Remote operation failed (exit code: " .. exit_code .. ")", vim.log.levels.ERROR)
      end
    end,
  })

  -- Start in insert mode
  vim.cmd("startinsert")

  -- Set up keybinding to close the window
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<CR>", {
    noremap = true,
    silent = true,
    desc = "Close floating terminal",
  })
end

return M
