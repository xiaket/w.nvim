-- tests/test_explorer_fs.lua
local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal

local child, hooks = H.new_child({ "init", "config", "layout", "explorer", "explorer.fs" })
local T = new_set({ hooks = hooks })

-- Helper to create test directories/files
local function create_test_dir()
  local dir = child.lua_get("vim.fn.tempname()")
  local cmd = [[
    local dir = ...
    -- Create base directory
    vim.fn.mkdir(dir, "p")
    return dir
  ]]
  child.lua(cmd, { dir })
  return dir
end

-- Test is_valid_directory()
T["is_valid_directory"] = new_set()

T["is_valid_directory"]["should_return_true_for_valid_directories"] = function()
  local test_dir = create_test_dir()
  local result = child.lua("return w.explorer.fs.is_valid_directory(...)", { test_dir })
  assert_equal(result, true)
end

T["is_valid_directory"]["should_return_false_for_non-existent_paths"] = function()
  local result = child.lua([[
    return w.explorer.fs.is_valid_directory("/path/that/does/not/exist")
  ]])
  assert_equal(result, false)
end

T["is_valid_directory"]["should_return_false_for_regular_files"] = function()
  local test_dir = create_test_dir()
  local cmd = string.format([[
    local dir = ...
    local file = dir .. "/test.txt"
    local f = io.open(file, "w")
    f:write("test")
    f:close()
    local fs = require('w.explorer.fs')
    return fs.is_valid_directory(file)
  ]])
  local result = child.lua(cmd, { test_dir })
  assert_equal(result, false)
end

-- Test read_dir()
T["read_dir"] = new_set()

T["read_dir"]["should_return_empty_list_for_invalid_directory"] = function()
  local result = child.lua([[
    local fs = require('w.explorer.fs')
    local files, truncated = fs.read_dir("/invalid/path")
    return { files = files, truncated = truncated }
  ]])
  assert_equal(#result.files, 0)
  assert_equal(result.truncated, false)
end

T["read_dir"]["should_handle_empty_directories"] = function()
  local test_dir = create_test_dir()
  local result = child.lua(
    [[
    local fs = require('w.explorer.fs')
    local files, truncated = fs.read_dir(...)
    return { files = files, truncated = truncated }
  ]],
    { test_dir }
  )
  assert_equal(#result.files, 0)
  assert_equal(result.truncated, false)
end

T["read_dir"]["should_sort_directories_first"] = function()
  local test_dir = create_test_dir()
  local cmd = [[
    local dir = ...
    -- Create mixed files and directories
    vim.fn.mkdir(dir .. "/z_dir", "p")
    vim.fn.mkdir(dir .. "/a_dir", "p")
    local f = io.open(dir .. "/b_file", "w")
    f:write("test")
    f:close()
    f = io.open(dir .. "/a_file", "w")
    f:write("test")
    f:close()
    
    -- Read directory
    local fs = require('w.explorer.fs')
    local files, _ = fs.read_dir(dir)
    
    -- Return just the names in order
    local names = {}
    for _, file in ipairs(files) do
      table.insert(names, file.name)
    end
    return names
  ]]
  local result = child.lua(cmd, { test_dir })

  -- Verify directories come first and each group is sorted alphabetically
  assert_equal(result[1], "a_dir")
  assert_equal(result[2], "z_dir")
  assert_equal(result[3], "a_file")
  assert_equal(result[4], "b_file")
end

T["read_dir"]["should_respect_max_files_limit"] = function()
  local test_dir = create_test_dir()
  local cmd = [[
    local dir = ...
    -- Create more files than max_files setting
    for i = 1, 10 do
      local f = io.open(dir .. "/" .. i .. ".txt", "w")
      f:write("test")
      f:close()
    end
    
    -- Set max_files config and read
    require('w.config').setup({ explorer = { max_files = 5 } })
    local fs = require('w.explorer.fs')
    local files, truncated = fs.read_dir(dir)
    return { count = #files, truncated = truncated }
  ]]
  local result = child.lua(cmd, { test_dir })
  assert_equal(result.count, 5) -- Should be limited to max_files
  assert_equal(result.truncated, true) -- Should indicate truncation
end

T["read_dir"]["should_handle_special_characters_in_names"] = function()
  local test_dir = create_test_dir()
  local cmd = [[
    local dir = ...
    -- Create files with special characters
    local special_names = {
      "with space.txt",
      "with.dots.txt", 
      "with_underscore.txt",
      "中文文件.txt",
      "!@#$%.txt"
    }
    
    for _, name in ipairs(special_names) do
      local f = io.open(dir .. "/" .. name, "w")
      f:write("test")
      f:close()
    end
    
    local fs = require('w.explorer.fs')
    local files, _ = fs.read_dir(dir)
    
    -- Return just the names
    local names = {}
    for _, file in ipairs(files) do
      table.insert(names, file.name)
    end
    table.sort(names)
    return names
  ]]
  local result = child.lua(cmd, { test_dir })
  assert_equal(#result, 5) -- Should find all files
  assert_equal(result[1], "!@#$%.txt") -- Verify special characters are preserved
end

return T
