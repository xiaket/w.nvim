local M = {}

-- Internal state
---@class ExplorerState
---@field _current_dir string current directory being displayed
---@field _window number|nil explorer window handle
---@field _buffer number|nil explorer buffer handle
---@field _last_position number|nil last cursor position in current directory
local _state = {
  _current_dir = vim.fn.getcwd(),
  _window = nil,
  _buffer = nil,
  _last_position = nil,
}

-- State access methods
---@return number|nil window handle if explorer window exists and is valid
function M.get_window()
  if _state._window and vim.api.nvim_win_is_valid(_state._window) then
    return _state._window
  end
  return nil
end

---@return number|nil buffer handle if explorer buffer exists and is valid
function M.get_buffer()
  if _state._buffer and vim.api.nvim_buf_is_valid(_state._buffer) then
    return _state._buffer
  end
  return nil
end

function M.get_last_position()
  return _state._last_position
end

---@return string
function M.get_current_dir()
  return _state._current_dir
end

-- State modification helpers
---@private
---@param win number|nil
function M.set_window(win)
  if win and not vim.api.nvim_win_is_valid(win) then
    return
  end
  _state._window = win
end

---@private
---@param buf number|nil
function M.set_buffer(buf)
  if buf and not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  _state._buffer = buf
end

---@private
---@param dir string
function M.set_current_dir(dir)
  _state._current_dir = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
end

---@private
---@param pos number|nil
function M.set_last_position(pos)
  if pos and (type(pos) ~= "number" or pos < 1) then
    return
  end
  _state._last_position = pos
end

return M
