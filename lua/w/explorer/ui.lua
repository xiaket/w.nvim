local M = {}

-- Dependencies
local config = require("w.config")
local debug = require("w.debug")
local autocmd = require("w.explorer.autocmd")
local state = require("w.explorer.state")

function M.highlight_current_file()
  local ns_id = vim.api.nvim_create_namespace(config.const.namespace)
  local buf = state.get_buffer()
  debug.log("highlight_current_file - start", buf, ns_id)

  if not buf then
    debug.log("highlight_current_file - no buffer")
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

local function configure_buffer(buf)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "filetype", config.const.filetype)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  autocmd.setup_buffer_autocmds(buf)
  autocmd.setup_buffer_keymaps(buf)
  state.set_buffer(buf)
end

---Create explorer buffer if not exists
function M.ensure_buffer()
  debug.dump_state("explorer enter ensure_buffer")
  local buf = state.get_buffer()

  -- Reuse existing buffer if valid
  if buf then
    debug.log("reusing existing buffer", buf)
    return
  end

  -- Create new buffer
  local new_buf = vim.api.nvim_create_buf(false, true)
  if not new_buf then
    debug.log("failed to create buffer")
    return
  end

  -- Set buffer options
  configure_buffer(new_buf)
  debug.dump_state("explorer exit ensure_buffer")
end

---Create explorer window
---@return number? win_id
function M.create_window()
  debug.dump_state("explorer enter create_window")

  M.ensure_buffer()
  local buf = state.get_buffer()
  debug.log("created new buf", buf)
  if not buf then
    -- We have added a debug line in ensure_buffer, ignore here.
    return nil
  end

  vim.cmd(
    -- Run split then run buffer command.
    string.format("topleft vertical %dsplit | buffer %d", config.options.explorer.window_width, buf)
  )
  local win = vim.api.nvim_get_current_win()

  -- Set window options
  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "winfixwidth", true)

  state.set_window(win)
  debug.dump_state("explorer exit create window")
  return win
end

---Display files in buffer
---@param files table list of files to display
---@param is_truncated boolean whether the list is truncated
function M.display_files(files, is_truncated)
  debug.dump_state("explorer enter display_files")
  debug.log("displaying", #files, "files", is_truncated and "(truncated)" or "")

  local buf = state.get_buffer()
  if not buf then
    debug.log("invalid buffer")
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
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  -- Set up 'j' mapping
  autocmd.setup_truncation_keymap(buf, is_truncated)

  debug.dump_state("explorer after display_files")
end

return M
