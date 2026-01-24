local M = {}

-- Dependencies
local config = require("w.config")

local actions = require("w.explorer.actions")
local state = require("w.explorer.state")
local fs = require("w.explorer.fs")
local ui = require("w.explorer.ui")

-- Expose state getters
M.get_window = state.get_window
M.get_buffer = state.get_buffer
M.get_current_dir = state.get_current_dir
M.get_last_position = state.get_last_position

---Close explorer window if it exists
function M.close()
  local win = state.get_window()
  if win then
    vim.api.nvim_win_close(win, false)
    state.set_window(nil)
  end
end

---Open explorer window
---@param dir? string directory to open, defaults to current_dir
function M.open(dir)
  if state.get_window() then
    return
  end

  local current_dir = M.get_current_dir()

  if dir then
    if not fs.is_valid_directory(dir) then
      return
    end
    current_dir = fs.normalize_path(dir)

    -- Close netrw buffer if present
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_option(buf, "filetype") == config.const.dir_filetype then
        vim.api.nvim_buf_delete(buf, { force = true })
        break
      end
    end
  end

  if not ui.create_window() then
    return
  end

  actions.refresh_display(current_dir)

  local last_position = M.get_last_position()
  if last_position then
    vim.fn.cursor(last_position, 0)
  end
end

---Toggle explorer window
function M.toggle_explorer()
  if state.get_window() then
    M.close()
  else
    M.open()
  end
end

return M
