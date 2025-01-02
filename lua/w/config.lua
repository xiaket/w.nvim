local M = {}

---@class Config
local defaults = {
  -- File explorer settings
  explorer_window_width = 25, -- default file explorer window width
  max_files = 100, -- maximum number of files in file explorer
  show_hidden = true, -- whether to show hidden files by default
  explorer_window_keymaps = { -- default keymaps in file explorer
    close = "q",
    go_up = "h",
    open = "<CR>",
  },
  -- Window management settings
  split_ratio = 0.618, -- golden ratio for window splits
  debug = false, -- enable debug
}

M.options = {}

---Validate configuration values
---@param config Config
---@return boolean, string? error message if validation fails
local function validate_config(config)
  -- Validate explorer window width
  if type(config.explorer_window_width) ~= "number" or config.explorer_window_width < 10 then
    return false, "explorer_window_width must be a number >= 10"
  end

  -- Validate max files
  if type(config.max_files) ~= "number" or config.max_files < 1 then
    return false, "max_files must be a positive number"
  end

  -- Validate split ratio
  if type(config.split_ratio) ~= "number" or config.split_ratio <= 0 or config.split_ratio >= 1 then
    return false, "split_ratio must be a number between 0 and 1"
  end

  -- Validate show_hidden
  if type(config.show_hidden) ~= "boolean" then
    return false, "show_hidden must be a boolean"
  end

  -- All validations passed
  return true
end

---Setup the plugin with user configuration
---@param user_config Config?
---@return boolean success
function M.setup(user_config)
  -- Merge configurations
  local config = vim.tbl_deep_extend("force", {}, defaults, user_config or {})

  -- Validate the merged config
  local valid, err = validate_config(config)
  if not valid then
    vim.notify("Config validation failed: " .. err, vim.log.levels.ERROR)
    return false
  end

  M.options = config
  return true
end

return M
