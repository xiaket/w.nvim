local M = {}

-- Dependencies
local layout = require("w.layout")
local util = require("w.layout.util")

local state = require("w.explorer.state")
local fs = require("w.explorer.fs")
local ui = require("w.explorer.ui")

---Refresh display with directory contents
---@param dir string directory to display
---@param ignore_max? boolean whether to ignore max files limit
function M.refresh_display(dir, ignore_max)
  local normalized = fs.normalize_path(dir)
  local files, is_truncated = fs.read_dir(normalized, ignore_max)
  state.set_current_dir(normalized)
  ui.display_files(files, is_truncated)
end

---Enter a directory
---@param dir string directory to open
function M.enter_dir(dir)
  M.refresh_display(dir)
end

---Navigate up one directory
function M.go_up()
  local current_dir = state.get_current_dir()
  local parent = vim.fn.fnamemodify(current_dir, ":h")

  if parent ~= current_dir then
    M.enter_dir(parent)
  end
end

function M.find_window_for_file(current_win)
  -- Try previous active window
  local target = layout.get_previous_active_window()
  if target and target ~= current_win and vim.api.nvim_win_is_valid(target) then
    return target
  end

  -- Try other non-explorer windows in current tab
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not util.is_explorer(win) then
      return win
    end
  end

  -- Create new split to the right
  vim.cmd("vsplit")
  return vim.api.nvim_get_current_win()
end

---Extract entry name from display line
---@param line string line content
---@return string|nil name or nil if invalid
local function extract_entry_name(line)
  local name = line:match("^[^ ]+ (.+)$")
  if not name or name:match("^%[.*%]$") then
    return nil
  end
  return name
end

---Open file or directory under cursor
function M.open_current()
  local win = state.get_window()
  if not win then
    return
  end

  local name = extract_entry_name(vim.api.nvim_get_current_line())
  if not name then
    return
  end

  local current_dir = state.get_current_dir()
  local path = vim.fn.fnamemodify(current_dir .. "/" .. name, ":p")

  if fs.is_valid_directory(path) then
    M.enter_dir(path)
  else
    local target_win = M.find_window_for_file(win)
    vim.api.nvim_set_current_win(target_win)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end
end

return M
