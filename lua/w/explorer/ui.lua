local M = {}

-- Dependencies
local config = require("w.config")
local autocmd = require("w.explorer.autocmd")
local state = require("w.explorer.state")

function M.highlight_current_file()
  local buf = state.get_buffer()
  if not buf then
    return
  end

  local ns_id = vim.api.nvim_create_namespace(config.const.namespace)
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

---Get file icon, using mini.icon if available, falling back to configured icons
---@param name string file name
---@param type string|nil file type (directory or file)
---@return string icon character
local function get_icon(name, type)
  -- Try using mini.icon if available
  local ok, mini_icon = pcall(require, "mini.icons")
  if ok then
    if type == "directory" then
      return mini_icon.get("directory", name)
    else
      return mini_icon.get("file", name)
    end
  end

  -- Fallback to configured icons
  return type == "directory" and config.options.explorer.icons.directory
    or config.options.explorer.icons.file
end

local function format_entries(files)
  local lines = {}
  for _, file in ipairs(files) do
    local icon = get_icon(file.name, file.type)
    table.insert(lines, icon .. " " .. file.name)
  end
  return lines
end

local function configure_buffer(buf)
  local opts = {
    buftype = "nofile",
    bufhidden = "wipe",
    filetype = config.const.filetype,
    modifiable = false,
    number = false,
    relativenumber = false,
    swapfile = false,
  }
  for k, v in pairs(opts) do
    vim.api.nvim_buf_set_option(buf, k, v)
  end

  autocmd.setup_buffer_autocmds(buf)
  autocmd.setup_buffer_keymaps(buf)
  state.set_buffer(buf)
end

---Create explorer buffer if not exists
function M.ensure_buffer()
  if state.get_buffer() then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  if buf then
    configure_buffer(buf)
  end
end

local function configure_window(win)
  local opts = {
    number = false,
    relativenumber = false,
    wrap = true,
    winfixwidth = true,
  }
  for k, v in pairs(opts) do
    vim.api.nvim_win_set_option(win, k, v)
  end
end

---Create explorer window
---@return number? win_id
function M.create_window()
  M.ensure_buffer()
  local buf = state.get_buffer()
  if not buf then
    return nil
  end

  vim.cmd(string.format("topleft vertical %dsplit | buffer %d", config.options.explorer.window_width, buf))
  local win = vim.api.nvim_get_current_win()

  configure_window(win)
  state.set_window(win)
  return win
end

---Display files in buffer
---@param files table list of files to display
---@param is_truncated boolean whether the list is truncated
function M.display_files(files, is_truncated)
  local buf = state.get_buffer()
  if not buf then
    return
  end

  local lines = format_entries(files)
  if is_truncated then
    table.insert(lines, "['j' to load more]")
  end

  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  autocmd.setup_truncation_keymap(buf, is_truncated)
end

return M
