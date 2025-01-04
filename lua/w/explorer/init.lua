local M = {}

-- Dependencies
local debug = require("w.debug")

local state = require("w.explorer.state")
local fs = require("w.explorer.fs")
local ui = require("w.explorer.ui")

-- Exposing the following things in state.
M.get_window = state.get_window
M.get_buffer = state.get_buffer
M.get_current_dir = state.get_current_dir
M.get_last_position = state.get_last_position

-- Public API
---Close explorer window if it exists
function M.close()
  debug.dump_state("explorer enter close")
  local win = state.get_window()
  if not win then
    return
  end

  -- Close window
  vim.api.nvim_win_close(win, false)
  state.set_window(nil)
  debug.dump_state("explorer exit close")
end

---Open explorer window
---@param dir? string directory to open, defaults to current_dir
function M.open(dir)
  debug.dump_state("explorer enter open")
  local win = state.get_window()
  debug.log("explorer", "open called", win and win or "nil")
  if win then
    debug.log("explorer", "explorer window already open")
    return
  end

  local current_dir = M.get_current_dir()

  -- Handle optional directory parameter
  if dir then
    -- Ensure dir exists and is directory
    local stat = vim.loop.fs_stat(dir)
    if not stat or stat.type ~= "directory" then
      debug.log("explorer", "invalid directory:", dir)
      return
    end

    -- Update state
    current_dir = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
    debug.log("explorer", "set directory to:", current_dir)
  end

  -- Create new window
  local _win = ui.create_window()
  if not _win then
    debug.log("explorer", "failed to create window")
    return
  end

  -- Load and display content
  local files, is_truncated = fs.read_dir(current_dir)
  state.set_current_dir(current_dir)
  ui.display_files(files, is_truncated)

  -- Restore position if available
  local last_position = M.get_last_position()
  if last_position then
    vim.fn.cursor(last_position, 0)
    debug.log("explorer", "restored cursor position", last_position)
  end
  debug.dump_state("explorer exit open")
end

---Toggle explorer window
function M.toggle_explorer()
  local win = state.get_window()
  if win then
    M.close()
  else
    M.open()
  end
end

return M
