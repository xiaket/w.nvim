local M = {}

-- Dependencies
local config = require("w.config")
local debug = require("w.debug")

local state = require("w.explorer.state")
local fs = require("w.explorer.fs")
local ui = require("w.explorer.ui")
local util = require("w.layout.util")

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
  debug.log("open called", win and win or "nil")
  if win then
    debug.log("explorer window already open")
    return
  end

  local current_dir = M.get_current_dir()

  -- Handle optional directory parameter
  if dir then
    -- Ensure dir exists and is directory
    local stat = vim.loop.fs_stat(dir)
    if not stat or stat.type ~= "directory" then
      debug.log("invalid directory:", dir)
      return
    end

    -- Update state
    current_dir = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
    debug.log("set directory to:", current_dir)

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_option(buf, "filetype") == config.const.dir_filetype then
        vim.api.nvim_buf_delete(buf, { force = true })
        debug.log("closed default dir buffer:", buf)
        break
      end
    end
  end

  -- Create new window
  local _win = ui.create_window()
  if not _win then
    debug.log("failed to create window")
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
    debug.log("restored cursor position", last_position)
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

function M.with_editor_window(callback)
  local current_win = vim.api.nvim_get_current_win()

  if util.is_explorer(current_win) then
    local last_active = require("w.layout").get_previous_active_window()
    if last_active and vim.api.nvim_win_is_valid(last_active) then
      vim.api.nvim_set_current_win(last_active)
    else
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if not util.is_explorer(win) then
          vim.api.nvim_set_current_win(win)
          break
        end
      end
    end
  end

  callback()
end

return M
