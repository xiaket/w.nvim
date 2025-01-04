local M = {}

-- Dependencies
local api = vim.api
local config = require("w.config")
local layout = require("w.layout")
local debug = require("w.debug")

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
local function set_window(win)
  if win and not vim.api.nvim_win_is_valid(win) then
    return
  end
  _state._window = win
end

---@private
---@param buf number|nil
local function set_buffer(buf)
  if buf and not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  _state._buffer = buf
end

---@private
---@param dir string
local function set_current_dir(dir)
  local stat = vim.loop.fs_stat(dir)
  if not stat or stat.type ~= "directory" then
    error(string.format("Invalid directory: %s", dir))
  end
  _state._current_dir = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
end

---@private
---@param pos number|nil
local function set_last_position(pos)
  if pos and (type(pos) ~= "number" or pos < 1) then
    return
  end
  _state._last_position = pos
end

local function highlight_current_file()
  local ns_id = vim.api.nvim_create_namespace("w_explorer_highlight")
  local buf = M.get_buffer()
  debug.log("explorer", "highlight_current_file - start", buf, ns_id)

  if not buf then
    debug.log("explorer", "highlight_current_file - no buffer")
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  local current = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
  if current == "" then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match(current .. "$") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "CursorLine", i - 1, 0, -1)
      break
    end
  end
end

-- Forward declarations for functions used in keymaps
local open_current, go_up

---Read directory contents with sorting and truncation
---@param path string directory path to read
---@param ignore_max? boolean whether to ignore max files limit
---@return table files, boolean is_truncated
local function read_dir(path, ignore_max)
  debug.log("explorer", "reading directory:", path, "ignore_max:", ignore_max or false)

  -- Ensure path exists and is directory
  local stat = vim.loop.fs_stat(path)
  if not stat or stat.type ~= "directory" then
    debug.log("explorer", "invalid directory:", path)
    return {}, false
  end

  local files = {}
  local handle = vim.loop.fs_scandir(path)
  local max_files = config.options.explorer.max_files
  local is_truncated = false

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Skip hidden files unless configured to show them
    if config.options.explorer.show_hidden or not name:match("^%.") then
      table.insert(files, { name = name, type = type })
    end

    -- Check max files limit
    if not ignore_max and #files >= max_files then
      -- Read one more to check if truncated
      if vim.loop.fs_scandir_next(handle) then
        is_truncated = true
      end
      break
    end
  end

  -- Sort: directories first, then alphabetically
  table.sort(files, function(a, b)
    if a.type == "directory" and b.type ~= "directory" then
      return true
    elseif a.type ~= "directory" and b.type == "directory" then
      return false
    else
      return a.name < b.name
    end
  end)

  debug.log("explorer", "found", #files, "files", is_truncated and "(truncated)" or "")
  return files, is_truncated
end

---Display files in buffer
---@param files table list of files to display
---@param is_truncated boolean whether the list is truncated
local function display_files(files, is_truncated)
  debug.dump_state("explorer enter display_files")
  debug.log("explorer", "displaying", #files, "files", is_truncated and "(truncated)" or "")

  local buf = M.get_buffer()
  if not buf then
    debug.log("explorer", "invalid buffer")
    return
  end

  -- Prepare lines
  local lines = {}
  for _, file in ipairs(files) do
    local prefix = file.type == "directory" and "󰉋 " or "󰈚 "
    table.insert(lines, prefix .. file.name)
  end

  if is_truncated then
    table.insert(lines, "['j' to load more]")
  end

  -- Update buffer content
  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_buf_set_option(buf, "modifiable", false)

  -- Set up 'j' mapping
  api.nvim_buf_set_keymap(buf, "n", "j", "", {
    callback = function()
      local cursor_line = api.nvim_win_get_cursor(0)[1]
      local line_count = api.nvim_buf_line_count(buf)

      -- Only intercept when truncated and cursor is on last line
      if is_truncated and cursor_line == line_count then
        local current_dir = M.get_current_dir()
        debug.log("explorer", "loading full directory")
        local full_files = read_dir(current_dir, true)
        display_files(full_files, false)
        return
      end

      -- Return '<Cmd>normal! j<CR>' for default behavior
      return "j"
    end,
    -- Using expr to make things like 2j(move down two lines) work.
    expr = true,
    noremap = true,
    silent = true,
  })

  debug.dump_state("explorer after display_files")
end

---Create cursor tracking for explorer buffer
---@param buf? number explorer buffer handle
local function track_cursor(buf)
  local group = vim.api.nvim_create_augroup("WExplorer", { clear = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      local win = M.get_window()
      if win then
        set_last_position(vim.api.nvim_win_get_cursor(win)[1])
      end
    end,
  })
end

---Create explorer buffer if not exists
local function ensure_buffer()
  debug.dump_state("explorer enter ensure_buffer")
  local buf = M.get_buffer()

  -- Reuse existing buffer if valid
  if buf then
    debug.log("explorer", "reusing existing buffer", buf)
    return
  end

  -- Create new buffer
  local new_buf = api.nvim_create_buf(false, true)
  if not new_buf then
    debug.log("explorer", "failed to create buffer")
    return
  end

  -- Set buffer options
  api.nvim_buf_set_option(new_buf, "buftype", "nofile")
  api.nvim_buf_set_option(new_buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(new_buf, "swapfile", false)
  api.nvim_buf_set_option(new_buf, "filetype", layout.EXPLORER_FILETYPE)
  api.nvim_buf_set_option(new_buf, "modifiable", false)

  -- Setup keymaps
  local function map(keys, callback)
    if type(keys) == "string" then
      keys = { keys }
    end

    for _, key in ipairs(keys) do
      api.nvim_buf_set_keymap(new_buf, "n", key, "", {
        callback = callback,
        noremap = true,
        silent = true,
      })
    end
  end

  map(config.options.explorer.keymaps.close, M.toggle_explorer)
  map(config.options.explorer.keymaps.go_up, go_up)
  map(config.options.explorer.keymaps.open, open_current)

  set_buffer(new_buf)
  track_cursor(new_buf)

  local group = vim.api.nvim_create_augroup("WExplorerHighlight", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = group,
    callback = highlight_current_file,
  })
  debug.dump_state("explorer exit ensure_buffer")
end

---Enter a directory
---@param dir string directory to open
local function enter_dir(dir)
  debug.log("explorer", "entering directory:", dir)
  local new_dir = dir:gsub("/$", "")
  set_current_dir(new_dir)
  local files, is_truncated = read_dir(new_dir)
  display_files(files, is_truncated)
end

---Create explorer window
---@return number? win_id
local function create_window()
  debug.dump_state("explorer enter create_window")

  ensure_buffer()
  local buf = M.get_buffer()
  debug.log("explorer", "created new buf", buf)
  if not buf then
    -- We have added a debug line in ensure_buffer, ignore here.
    return nil
  end

  vim.cmd(
    -- Run split then run buffer command.
    string.format("topleft vertical %dsplit | buffer %d", config.options.explorer.window_width, buf)
  )
  local win = api.nvim_get_current_win()
  debug.log(
    "explorer",
    string.format(
      "After window creation - win: %d, buf: %d, width: %d, ft: %s",
      win,
      vim.api.nvim_win_get_buf(win),
      vim.api.nvim_win_get_width(win),
      vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(win), "filetype")
    )
  )
  debug.dump_state("explorer create window")

  -- Set window options
  api.nvim_win_set_option(win, "number", false)
  api.nvim_win_set_option(win, "relativenumber", false)
  api.nvim_win_set_option(win, "wrap", true)
  -- TODO: maybe we can simplify window size calculation using this flag.
  api.nvim_win_set_option(win, "winfixwidth", true)

  set_window(win)
  debug.dump_state("explorer exit create window")
  return win
end

---Navigate up one directory
go_up = function()
  local current_dir = M.get_current_dir()
  debug.dump_state("explorer enter go_up")

  local parent = vim.fn.fnamemodify(current_dir, ":h")

  if parent == current_dir then
    debug.log("explorer", "already at root")
  else
    enter_dir(parent)
  end

  debug.dump_state("explorer exit go_up")
end

---Open file or directory under cursor
open_current = function()
  debug.dump_state("explorer enter open_current")

  local win = M.get_window()
  if not win then
    debug.log("explorer", "invalid window")
    return
  end

  -- Get current line and extract name
  local line = api.nvim_get_current_line()
  local name = line:match("^.+%s(.+)$")
  if not name then
    debug.log("explorer", "could not extract name from line:", line)
    return
  end

  -- Construct full path
  local current_dir = M.get_current_dir()
  local path = vim.fn.fnamemodify(current_dir .. "/" .. name, ":p")
  local stat = vim.loop.fs_stat(path)
  if not stat then
    debug.log("explorer", "could not stat path:", path)
    return
  end

  if stat.type == "directory" then
    -- Enter directory
    enter_dir(path)
  else
    -- Open file in appropriate window
    debug.log("explorer", "opening file:", path)

    -- Get target window for file
    local target_win = layout.get_previous_active_window()
    debug.log("explorer", "initial target window:", target_win and target_win or "nil")

    if not target_win or target_win == win then
      -- If no active split or it's the explorer window, try to find another window
      local wins = api.nvim_tabpage_list_wins(0)
      for _, _win in ipairs(wins) do
        if _win ~= win then
          target_win = _win
          debug.log("explorer", "found alternative window:", _win)
          break
        end
      end

      -- If still no target window, create a new split
      if not target_win then
        local saved_win = api.nvim_get_current_win()
        vim.cmd("wincmd l") -- Move right
        if api.nvim_get_current_win() == saved_win then
          vim.cmd("vsplit") -- Create new split if at rightmost window
        end
        target_win = api.nvim_get_current_win()
        debug.log("explorer", "created new target window:", target_win)
      end
    end

    -- Open file in target window
    api.nvim_set_current_win(target_win)
    debug.log("explorer", "switching to target window:", target_win)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end

  debug.dump_state("explorer exit open_current")
end

-- Public API
---Close explorer window if it exists
function M.close()
  debug.dump_state("explorer enter close")
  local win = M.get_window()
  if not win then
    return
  end

  -- Close window
  api.nvim_win_close(win, false)
  set_window(nil)
  debug.dump_state("explorer exit close")
end

---Open explorer window
---@param dir? string directory to open, defaults to current_dir
function M.open(dir)
  debug.dump_state("explorer enter open")
  local win = M.get_window()
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
    set_current_dir(current_dir)
    debug.log("explorer", "set directory to:", current_dir)
  end

  -- Create new window
  local _win = create_window()
  if not _win then
    debug.log("explorer", "failed to create window")
    return
  end

  -- Load and display content
  local files, is_truncated = read_dir(current_dir)
  display_files(files, is_truncated)

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
  local win = M.get_window()
  if win then
    M.close()
  else
    M.open()
  end
end

return M
