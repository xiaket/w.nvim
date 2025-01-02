local M = {}

-- Dependencies
local api = vim.api
local fn = vim.fn
local config = require("w.config")
local layout = require("w.layout")
local debug = require("w.debug") -- Import the debug module
local ns_id = vim.api.nvim_create_namespace("explorer_highlight")

-- Internal state
---@class ExplorerState
---@field current_dir string current directory being displayed
---@field window number? explorer window handle
---@field buffer number? explorer buffer handle
---@field last_position number? last cursor position in current directory
---@field current_file string? path of current file being edited
---@field ready boolean whether the explorer is ready
local state = {
  current_dir = fn.getcwd(),
  window = nil,
  buffer = nil,
  last_position = nil,
  current_file = nil,
  ready = false,
}

---Highlight current file in explorer if visible
local function highlight_current_file()
  if not state.buffer or not api.nvim_buf_is_valid(state.buffer) or not state.current_file then
    return
  end

  -- Clear existing highlights
  api.nvim_buf_clear_namespace(state.buffer, ns_id, 0, -1)

  -- Get current file name
  local current_name = fn.fnamemodify(state.current_file, ":t")
  if current_name == "" then
    return
  end

  -- Find and highlight the line
  local lines = api.nvim_buf_get_lines(state.buffer, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match(" " .. vim.pesc(current_name) .. "$") then
      api.nvim_buf_add_highlight(state.buffer, ns_id, "CursorLine", i - 1, 0, -1)
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
  local max_files = config.options.max_files
  local is_truncated = false

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Skip hidden files unless configured to show them
    if config.options.show_hidden or not name:match("^%.") then
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
  debug.log("explorer", "displaying", #files, "files", is_truncated and "(truncated)" or "")
  debug.dump_buffers("explorer Before display_files")

  if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
    debug.log("explorer", "invalid buffer")
    return
  end

  -- Save cursor position
  local current_pos = state.window
      and api.nvim_win_is_valid(state.window)
      and api.nvim_win_get_cursor(state.window)
    or { 1, 0 }

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
  api.nvim_buf_set_option(state.buffer, "modifiable", true)
  api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
  api.nvim_buf_set_option(state.buffer, "modifiable", false)

  -- Set up 'j' mapping
  pcall(api.nvim_buf_del_keymap, state.buffer, "n", "j")
  if is_truncated then
    api.nvim_buf_set_keymap(state.buffer, "n", "j", "", {
      callback = function()
        local cursor_line = api.nvim_win_get_cursor(0)[1]
        local line_count = api.nvim_buf_line_count(state.buffer)
        if cursor_line == line_count then
          -- Load full directory
          debug.log("explorer", "loading full directory")
          local full_files = read_dir(state.current_dir, true)
          display_files(full_files, false)
        else
          vim.cmd("normal! j")
        end
      end,
      noremap = true,
      silent = true,
    })
  else
    api.nvim_buf_set_keymap(state.buffer, "n", "j", "j", { noremap = true, silent = true })
  end

  -- Restore position if valid
  if current_pos[1] <= #lines then
    if state.window and api.nvim_win_is_valid(state.window) then
      api.nvim_win_set_cursor(state.window, current_pos)
    end
  end

  -- Highlight current file
  highlight_current_file()

  debug.dump_buffers("explorer After display_files")
end

---Create explorer buffer if not exists
---@return number? buf_id
local function ensure_buffer()
  debug.log(
    "explorer",
    "ensuring buffer exists",
    state.buffer and debug.format_buf(state.buffer) or "nil"
  )
  debug.dump_buffers("explorer Before ensure_buffer")

  -- Reuse existing buffer if valid
  if state.buffer and api.nvim_buf_is_valid(state.buffer) then
    debug.log("explorer", "reusing existing buffer", debug.format_buf(state.buffer))
    return state.buffer
  end

  -- Create new buffer
  local buf = api.nvim_create_buf(false, true)
  if not buf then
    debug.log("explorer", "failed to create buffer")
    return nil
  end

  -- Set buffer options
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(buf, "swapfile", false)
  api.nvim_buf_set_option(buf, "filetype", layout.EXPLORER_FILETYPE)
  api.nvim_buf_set_option(buf, "modifiable", false)

  -- Setup keymaps
  local function map(key, callback)
    api.nvim_buf_set_keymap(buf, "n", key, "", {
      callback = callback,
      noremap = true,
      silent = true,
    })
  end

  map(config.options.explorer_window_keymaps.close, M.toggle_explorer)
  map(config.options.explorer_window_keymaps.go_up, go_up)
  map(config.options.explorer_window_keymaps.open, open_current)

  state.buffer = buf
  debug.log("explorer", "created new buffer", debug.format_buf(buf))
  debug.dump_buffers("explorer After ensure_buffer")
  return buf
end

---Create explorer window
---@return number? win_id
local function create_window()
  debug.log("explorer", "creating window")
  debug.dump_buffers("explorer Before create_window")

  state.ready = false
  local buf = ensure_buffer()
  if not buf then
    return nil
  end

  vim.cmd(
    string.format("topleft vertical %dsplit | buffer %d", config.options.explorer_window_width, buf)
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
  state.ready = true

  -- Set window options
  api.nvim_win_set_option(win, "number", false)
  api.nvim_win_set_option(win, "relativenumber", false)
  api.nvim_win_set_option(win, "wrap", false)
  api.nvim_win_set_option(win, "winfixwidth", true)

  state.window = win
  debug.log("explorer", "created window", debug.format_win(win))
  debug.dump_buffers("explorer After create_window")
  return win
end

---Navigate up one directory
go_up = function()
  debug.log("explorer", "going up from", state.current_dir)
  debug.dump_buffers("explorer Before go_up")

  local parent = fn.fnamemodify(state.current_dir, ":h")

  if parent ~= state.current_dir then
    state.current_dir = parent:gsub("/$", "")
    local files, is_truncated = read_dir(state.current_dir)
    display_files(files, is_truncated)
    state.last_position = 1
  else
    debug.log("explorer", "already at root")
  end

  debug.dump_buffers("explorer After go_up")
end

---Open file or directory under cursor
open_current = function()
  debug.log("explorer", "opening current item")
  debug.dump_buffers("explorer Before open_current")

  if not state.window or not api.nvim_win_is_valid(state.window) then
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
  local path = fn.fnamemodify(state.current_dir .. "/" .. name, ":p")
  local stat = vim.loop.fs_stat(path)
  if not stat then
    debug.log("explorer", "could not stat path:", path)
    return
  end

  if stat.type == "directory" then
    -- Enter directory
    debug.log("explorer", "entering directory:", path)
    state.current_dir = path:gsub("/$", "")
    local files, is_truncated = read_dir(state.current_dir)
    display_files(files, is_truncated)
    state.last_position = 1
  else
    -- Open file in appropriate window
    debug.log("explorer", "opening file:", path)

    -- Get target window for file
    local target_win = layout.get_previous_active_window()
    debug.log(
      "explorer",
      "initial target window:",
      target_win and debug.format_win(target_win) or "nil"
    )

    if not target_win or target_win == state.window then
      -- If no active split or it's the explorer window, try to find another window
      local wins = api.nvim_tabpage_list_wins(0)
      for _, win in ipairs(wins) do
        if win ~= state.window then
          target_win = win
          debug.log("explorer", "found alternative window:", debug.format_win(win))
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
        debug.log("explorer", "created new target window:", debug.format_win(target_win))
      end
    end

    -- Open file in target window
    api.nvim_set_current_win(target_win)
    debug.log("explorer", "switching to target window:", debug.format_win(target_win))
    state.ready = false
    vim.cmd("edit " .. fn.fnameescape(path))
    state.current_file = path

    -- Return to explorer window and highlight current file
    api.nvim_set_current_win(state.window)
    highlight_current_file()
    state.ready = true
    api.nvim_set_current_win(target_win)
  end

  debug.dump_buffers("explorer After open_current")
end

-- Public API
---Close explorer window if it exists
function M.close()
  debug.log("explorer", "close called", state.window and debug.format_win(state.window) or "nil")
  if not (state.window and api.nvim_win_is_valid(state.window)) then
    return
  end

  -- Save position before closing
  state.last_position = api.nvim_win_get_cursor(state.window)[1]

  -- Close window
  api.nvim_win_close(state.window, false)
  state.window = nil
  debug.log("explorer", "closed window, saved position:", state.last_position)

  -- Trigger layout redraw
  layout.redraw()
end

---Open explorer window
---@param dir? string directory to open, defaults to current_dir
function M.open(dir)
  debug.log("explorer", "open called", state.window and debug.format_win(state.window) or "nil")
  if state.window and api.nvim_win_is_valid(state.window) then
    return
  end

  -- Handle optional directory parameter
  if dir then
    -- Ensure dir exists and is directory
    local stat = vim.loop.fs_stat(dir)
    if not stat or stat.type ~= "directory" then
      debug.log("explorer", "invalid directory:", dir)
      return
    end

    -- Update state
    state.current_dir = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
    debug.log("explorer", "set directory to:", state.current_dir)
  end

  -- Create new window
  local win = create_window()
  if not win then
    debug.log("explorer", "failed to create window")
    return
  end

  -- Load and display content
  local files, is_truncated = read_dir(state.current_dir)
  display_files(files, is_truncated)

  -- Restore position if available
  if state.last_position then
    local line_count = api.nvim_buf_line_count(state.buffer)
    if state.last_position <= line_count then
      api.nvim_win_set_cursor(win, { state.last_position, 0 })
      debug.log("explorer", "restored cursor position", state.last_position)
    end
  end

  -- Store current file path if any
  local current_buf = api.nvim_get_current_buf()
  local current_name = api.nvim_buf_get_name(current_buf)
  if current_name ~= "" then
    state.current_file = current_name
    highlight_current_file()
  end

  -- Trigger layout redraw
  layout.redraw()
end

---Toggle explorer window
function M.toggle_explorer()
  if state.window and api.nvim_win_is_valid(state.window) then
    M.close()
  else
    M.open()
  end
end

function M.get_state()
  return state
end

return M
