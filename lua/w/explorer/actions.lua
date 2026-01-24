local M = {}

-- Dependencies
local layout = require("w.layout")
local debug = require("w.debug")

local state = require("w.explorer.state")
local fs = require("w.explorer.fs")
local ui = require("w.explorer.ui")

---Enter a directory
---@param dir string directory to open
function M.enter_dir(dir)
  debug.log("entering directory:", dir)
  local new_dir = fs.normalize_path(dir)
  local files, is_truncated = fs.read_dir(new_dir)
  state.set_current_dir(new_dir)
  ui.display_files(files, is_truncated)
end

---Navigate up one directory
function M.go_up()
  local current_dir = state.get_current_dir()
  debug.dump_state("explorer enter go_up")

  local parent = vim.fn.fnamemodify(current_dir, ":h")

  if parent == current_dir then
    debug.log("already at root")
  else
    M.enter_dir(parent)
  end

  debug.dump_state("explorer exit go_up")
end

function M.find_window_for_file(current_win)
  -- Try previous active window
  local target = layout.get_previous_active_window()
  if target and target ~= current_win and vim.api.nvim_win_is_valid(target) then
    return target
  end

  -- Try other existing windows
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= current_win then
      return win
    end
  end

  -- Create new split
  local saved_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l") -- Move right
  if vim.api.nvim_get_current_win() == saved_win then
    vim.cmd("vsplit") -- Create new split if at rightmost window
  end
  return vim.api.nvim_get_current_win()
end

---Open file or directory under cursor
function M.open_current()
  debug.dump_state("explorer enter open_current")

  local win = state.get_window()
  if not win then
    debug.log("invalid window")
    return
  end

  -- Get current line and extract name
  local line = vim.api.nvim_get_current_line()
  -- remove icon and space from the line.
  local name = line:match("^[^ ]+ (.+)$")
  if not name then
    debug.log("could not extract name from line:", line)
    return
  end

  -- Skip ['j' to load more]
  if name:match("^%[.*%]$") then
    return
  end

  -- Construct full path
  local current_dir = state.get_current_dir()
  local path = vim.fn.fnamemodify(current_dir .. "/" .. name, ":p")
  local stat = vim.loop.fs_stat(path)
  if not stat then
    debug.log("could not stat path:", path)
    return
  end

  if stat.type == "directory" then
    -- Enter directory
    M.enter_dir(path)
  else
    -- Open file in appropriate window
    debug.log("opening file:", path)

    local target_win = M.find_window_for_file(win)
    -- Open file in target window
    vim.api.nvim_set_current_win(target_win)
    debug.log("switching to target window:", target_win)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end

  debug.dump_state("explorer exit open_current")
end

return M
