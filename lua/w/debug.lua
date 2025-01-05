-- debug.lua
local M = {}

if os.getenv("W_DEBUG") then
  -- Enable or disable debug globally
  M.enabled = true
  -- log file path instead of stdout
  M.log_file_path = "/tmp/w-debug.log"
else
  M.enabled = false
  M.log_file_path = nil
end
local log_file = nil

---Get current timestamp
---@return string|osdate formatted timestamp
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

---Ensure log file is open
local function ensure_log_file()
  if log_file then
    return
  end

  if M.log_file_path == nil then
    log_file = io.stdout
  else
    log_file = io.open(M.log_file_path, "w")
    if not log_file then
      error("Could not open log file: " .. M.log_file_path)
    end
  end
end

---Format buffer information into string
---@param buf number buffer handle
---@return string formatted buffer information
local function format_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return string.format("buf:%d (invalid)", buf)
  end
  local name = vim.fn.bufname(buf)
  local ft = vim.api.nvim_buf_get_option(buf, "filetype")
  local listed = vim.api.nvim_buf_get_option(buf, "buflisted")
  local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
  return string.format("buf:%d name:%s ft:%s listed:%s type:%s", buf, name, ft, listed, buftype)
end

---Format window information into string
---@param win number|nil window handle
---@return string formatted window information
local function format_win(win)
  if win == nil then
    return "win:nil"
  end
  if not vim.api.nvim_win_is_valid(win) then
    return string.format("win:%d (invalid)", win)
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local width = vim.api.nvim_win_get_width(win)
  local ft = vim.api.nvim_buf_get_option(buf, "filetype")
  return string.format("win:%d buf:%d ft:%s width:%d", win, buf, ft, width)
end

---Log debug information with a prefix and timestamp
---@param prefix string prefix for the log
---@param ... any additional information to log
function M.log(prefix, ...)
  if not M.enabled then
    return
  end

  ensure_log_file()

  local parts = vim.tbl_map(tostring, { ... })
  local message = string.format("[%s] %s %s\n", get_timestamp(), prefix, table.concat(parts, " "))

  -- Write the message to the log file
  if log_file then
    log_file:write(message)
    log_file:flush()
  end
end

---Format layout tree node into string representation
---@param node table layout tree node
---@param indent number current indentation level
---@return string formatted node representation
local function format_layout_node(node, indent)
  local node_type = node[1]
  local content = node[2]
  local prefix = string.rep("  ", indent)

  if node_type == "leaf" then
    return prefix .. format_win(content)
  end

  local lines = { prefix .. node_type }
  for _, child in ipairs(content) do
    table.insert(lines, format_layout_node(child, indent + 1))
  end
  return table.concat(lines, "\n")
end

---Dump complete editor state including buffers, windows, and layout
---@param prefix string? optional prefix for the log message (default: "state")
function M.dump_state(prefix)
  if not M.enabled then
    return
  end

  prefix = prefix or "state"
  local current_win = vim.api.nvim_get_current_win()

  -- Log buffers section
  M.log(prefix, "=== Buffers ===")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      M.log(prefix, "  " .. format_buf(buf))
    end
  end

  -- Log windows section
  M.log(prefix, "=== Windows ===")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local active = win == current_win and " (active)" or ""
    M.log(prefix, "  " .. format_win(win) .. active)
  end

  -- Log layout section
  M.log(prefix, "=== Layout ===")
  local tree = vim.fn.winlayout()
  -- Split layout into lines and log each line separately
  for line in format_layout_node(tree, 0):gmatch("[^\n]+") do
    M.log(prefix, "  " .. line)
  end

  -- Log current state information
  M.log(prefix, "=== Snapshot ===")
  -- Current window and buffer info
  M.log(prefix, string.format("  Current window: %s", format_win(vim.api.nvim_get_current_win())))
  M.log(
    prefix,
    string.format(
      "  Previous window: %s",
      package.loaded["w.layout"]
          and format_win(package.loaded["w.layout"].get_previous_active_window())
        or "N/A"
    )
  )

  -- Explorer state if module is loaded
  if package.loaded["w.explorer"] then
    local explorer = package.loaded["w.explorer"]
    local win = explorer.get_window()
    local buf = explorer.get_buffer()
    local last_position = explorer.get_last_position()
    M.log(prefix, string.format("  Explorer state:"))
    M.log(prefix, string.format("    Current dir: %s", explorer.get_current_dir() or "nil"))
    M.log(prefix, string.format("    Window: %s", win and format_win(win) or "nil"))
    M.log(prefix, string.format("    Buffer: %s", buf and format_buf(buf) or "nil"))
    M.log(prefix, string.format("    Last position: %s", last_position or "nil"))
  end
end

local function cleanup()
  if log_file and log_file ~= io.stdout then
    log_file:close()
    log_file = nil
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", { callback = cleanup })

return M
