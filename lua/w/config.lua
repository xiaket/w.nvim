local M = {}

---@class ExplorerConfig
---@field window_width number default file explorer window width
---@field max_files number maximum number of files in file explorer
---@field show_hidden boolean whether to show hidden files by default
---@field keymaps table default keymaps in file explorer
local ExplorerDefaults = {
  window_width = 25,
  max_files = 100,
  show_hidden = true,
  keymaps = {
    close = { "q" },
    go_up = { "h" },
    open = { "<CR>" },
  },
}

---@class Config
---@field explorer ExplorerConfig explorer configuration
---@field split_ratio number golden ratio for window splits
---@field debug boolean enable debug
local defaults = {
  explorer = ExplorerDefaults,
  split_ratio = 0.618,
  debug = false,
}

M.options = {}

-- Helper function to check config keys against reference keys
---@param config table configuration table to check
---@param reference table reference table containing valid keys
---@param prefix string? prefix for error messages in nested tables
---@return boolean is_valid
---@return string? error_message
local function validate_keys(config, reference, prefix)
  prefix = prefix or ""

  -- Check each key in config against reference
  for key, value in pairs(config) do
    if reference[key] == nil then
      return false, string.format("Unknown configuration key '%s%s'", prefix, key)
    end
    -- Recursively validate nested tables
    if type(value) == "table" and type(reference[key]) == "table" then
      local valid, err = validate_keys(value, reference[key], prefix .. key .. ".")
      if not valid then
        return false, err
      end
    end
  end

  return true
end

---Validate explorer configuration values
---@param config ExplorerConfig
---@return boolean valid
---@return string? error_message
local function validate_explorer_config(config)
  -- Check explorer config keys against defaults
  local valid, err = validate_keys(config, ExplorerDefaults, "explorer.")
  if not valid then
    return false, err
  end

  -- Check keymap keys against defaults
  valid, err = validate_keys(config.keymaps, ExplorerDefaults.keymaps, "explorer.keymaps.")
  if not valid then
    return false, err
  end

  if type(config.window_width) ~= "number" or config.window_width < 10 then
    return false, "explorer.window_width must be a number >= 10"
  end

  if type(config.max_files) ~= "number" or config.max_files < 1 then
    return false, "explorer.max_files must be a positive number"
  end

  if type(config.show_hidden) ~= "boolean" then
    return false, "explorer.show_hidden must be a boolean"
  end

  if type(config.keymaps) ~= "table" then
    return false, "explorer.keymaps must be a table"
  end

  local required_keys = { "close", "go_up", "open" }
  local key_type
  for _, key in ipairs(required_keys) do
    key_type = type(config.keymaps[key])
    if key_type ~= "string" and key_type ~= "table" then
      return false, string.format("explorer.keymaps.%s must be a string or a table", key)
    end
  end

  return true
end

---Validate configuration values
---@param config Config
---@return boolean valid
---@return string? error_message
local function validate_config(config)
  -- Check root config keys against defaults
  local valid, err = validate_keys(config, defaults)
  if not valid then
    return false, err
  end

  if type(config.explorer) ~= "table" then
    return false, "explorer must be a table"
  end

  local explorer_valid, explorer_error = validate_explorer_config(config.explorer)
  if not explorer_valid then
    return false, explorer_error
  end

  if
    type(config.split_ratio) ~= "number"
    or config.split_ratio < 0.5
    or config.split_ratio >= 1
  then
    return false, "split_ratio must be a number between 0.5 and 1"
  end

  if type(config.debug) ~= "boolean" then
    return false, "debug must be a boolean"
  end

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
