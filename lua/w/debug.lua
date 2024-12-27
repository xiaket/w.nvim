-- debug.lua
local M = {}

-- Enable or disable debug globally
M.enabled = true
-- log file path instead of stdout
M.log_file_path = "/tmp/lua-debug.log"
local log_file
if M.log_file_path then
  log_file = io.open(M.log_file_path, "w")
else
  log_file = io.stdout
end

---Get current timestamp
---@return string|osdate formatted timestamp
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

---Log debug information with a prefix and timestamp
---@param prefix string prefix for the log
---@param ... any additional information to log
function M.log(prefix, ...)
  if not M.enabled then
    return
  end
  local parts = vim.tbl_map(tostring, { ... })
  local message = string.format("[%s] %s %s\n", get_timestamp(), prefix, table.concat(parts, " "))

  -- Write the message to the log file
  if log_file then
    log_file:write(message)
    log_file:flush()
  else
    error("Log file is not available for writing.")
  end
end

---Format window information into string
---@param win number? window handle
---@return string formatted window information
function M.format_win(win)
  if not vim.api.nvim_win_is_valid(win) then
    return string.format("win:%d (invalid)", win)
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local width = vim.api.nvim_win_get_width(win)
  return string.format("win:%d buf:%d width:%d", win, buf, width)
end

---Format buffer information into string
---@param buf number buffer handle
---@return string formatted buffer information
function M.format_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return string.format("buf:%d (invalid)", buf)
  end
  local name = vim.fn.bufname(buf)
  local ft = vim.api.nvim_buf_get_option(buf, "filetype")
  local listed = vim.api.nvim_buf_get_option(buf, "buflisted")
  local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
  return string.format("buf:%d name:%s ft:%s listed:%s type:%s", buf, name, ft, listed, buftype)
end

---Dump all buffer information
---@param prefix string prefix for the log
function M.dump_buffers(prefix)
  if not M.enabled then
    return
  end
  M.log(prefix, "buffer list:")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      M.log("  ", M.format_buf(buf))
    end
  end
end

return M
