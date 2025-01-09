local M = {}

-- Dependencies
local config = require("w.config")
local debug = require("w.debug")

function M.is_valid_directory(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "directory"
end

---Read directory contents with sorting and truncation
---@param path string directory path to read
---@param ignore_max? boolean whether to ignore max files limit
---@return table files, boolean is_truncated
function M.read_dir(path, ignore_max)
  debug.log("explorer", "reading directory:", path, "ignore_max:", ignore_max or false)

  if not M.is_valid_directory(path) then
    debug.log("explorer", "invalid directory:", path)
    return {}, false
  end

  local files = {}
  local handle, err = vim.loop.fs_scandir(path)

  if not handle then
    debug.log("explorer", "error scanning directory:", err)
    vim.notify("Error reading directory: " .. err, vim.log.levels.ERROR)
    return {}, false
  end

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

return M
