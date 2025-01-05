-- tests/test_explorer.lua
local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal

-- Create child process with required modules
local child, hooks = H.new_child({ "init", "config", "layout", "explorer" })

-- Create test set with hooks
local T = new_set({ hooks = hooks })

local get_key = function(path)
  local keys = child.lua_get(path)
  if type(keys) == "table" then
    return keys[1]
  else
    return keys
  end
end

local function create_test_dir()
  local dir = child.lua_get("vim.fn.tempname()")
  local cmd = [[
    local dir = ...
    local files = {
      "normal.file",
      "file1.txt",
      "file2.lua",
      "测试文件.md",
      ".hidden_file",
      "Program Files/test.md",
      "temp_dir/nested_file.txt",
      "empty_dir/",
    }

    -- Try to delete first if exists
    if vim.fn.isdirectory(dir) == 1 then
      vim.fn.delete(dir, "rf")
    end
    -- Create fresh directory
    vim.fn.mkdir(dir, "p")

    -- Create files
    for _, file in ipairs(files) do
      if file:match("/$") then
        vim.fn.mkdir(dir .. "/" .. file:sub(1, -2), "p")
      else
        local _dir = file:match("(.+)/")
        if _dir then
          vim.fn.mkdir(dir .. "/" .. _dir, "p")
        end
        local f = io.open(dir .. "/" .. file, "w")
        if f then
          f:write("Test content")
          f:close()
        end
      end
    end
  ]]

  child.lua(cmd, { dir })
  return dir
end

local function find_line_in_explorer(pattern)
  local cmd = [[
    local lines = vim.api.nvim_buf_get_lines(w.explorer.get_buffer(), 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match(...) then return { found = true, index = i} end
    end
    return { found = false, index = -1 }
  ]]
  return child.lua(cmd, { pattern })
end

local function open_explorer_with(test_dir, opts)
  if opts == nil then
    opts = {}
  end
  child.lua("w.config.setup(...)", { opts })
  child.lua("w.explorer.open(...)", { test_dir })
end

-- Test explorer toggle functionality
T["toggle_explorer"] = new_set()

T["toggle_explorer"]["should_create_and_close_explorer_window"] = function()
  assert_equal(#child.api.nvim_list_wins(), 1, "Should start with exactly one window")
  child.lua("w.explorer.open()")
  assert_equal(#child.api.nvim_list_wins(), 2, "Should have two windows after open")

  local win = child.lua_get("w.explorer.get_window()")
  local width = child.api.nvim_win_get_width(win)
  assert_equal(width, child.lua_get("w.config.options.explorer.window_width"))

  -- Toggle explorer off
  child.lua("w.explorer.close()")
  assert_equal(#child.api.nvim_list_wins(), 1, "Should end with exactly one window")
end

T["toggle_explorer"]["should_create_new_splits_with_explorer_window"] = function()
  assert_equal(#child.api.nvim_list_wins(), 1, "Should start with exactly one window")
  child.lua("w.explorer.open()")
  child.lua("w.layout.split('right')")
  child.lua("w.layout.split('right')")
  assert_equal(
    #child.api.nvim_list_wins(),
    3,
    "Should have two windows with another explorer window"
  )

  local win = child.lua_get("w.explorer.get_window()")
  local width = child.api.nvim_win_get_width(win)
  assert_equal(width, child.lua_get("w.config.options.explorer.window_width"))
end

-- Test directory reading and display
T["directory_reading"] = new_set({
  parametrize = {
    { true }, -- show_hidden = true
    { false }, -- show_hidden = false
  },
})

T["directory_reading"]["should_respect_show_hidden_setting"] = function(show_hidden)
  local test_dir = create_test_dir()

  -- Setup config with parametrized value
  open_explorer_with(test_dir, { explorer = { show_hidden = show_hidden } })
  assert_equal(find_line_in_explorer("%.hidden_file$").found, show_hidden)
  assert_equal(find_line_in_explorer("normal.file$").found, true)
  assert_equal(find_line_in_explorer("temp_dir$").found, true)
end

T["directory_reading"]["should_respect_max_files_setting"] = function()
  local test_dir = create_test_dir()
  open_explorer_with(test_dir, { explorer = { max_files = 3 } })

  local buf = child.lua_get("w.explorer.get_buffer()")
  assert_equal(find_line_in_explorer("['j' to load more]").found, true)
  assert_equal(#child.api.nvim_buf_get_lines(buf, 0, -1, false) < 5, true)
end

-- Test navigation functionality
T["navigation"] = new_set()

T["navigation"]["should_restore_cursor_position"] = function()
  local test_dir = create_test_dir()
  open_explorer_with(test_dir)

  local win = child.lua_get("w.explorer.get_window()")
  child.api.nvim_win_set_cursor(win, { 3, 0 })

  child.lua("w.explorer.close()")
  child.lua("w.explorer.open()")

  local cursor = child.api.nvim_win_get_cursor(child.lua_get("w.explorer.get_window()"))
  assert_equal(cursor[1], 3)
end

T["navigation"]["should_navigate_directories"] = function()
  local test_dir = create_test_dir()
  open_explorer_with(test_dir)

  local result = find_line_in_explorer("Program Files$")
  assert_equal(result.found, true)
  local win = child.lua_get("w.explorer.get_window()")
  assert_equal(result.found, true)

  -- Navigate to 'Program Files' and open it
  child.api.nvim_win_set_cursor(win, { result.index, 0 })
  child.type_keys(get_key("w.config.options.explorer.keymaps.open"))
  assert_equal(find_line_in_explorer("test.md$").found, true)

  -- Test going up
  child.type_keys(get_key("w.config.options.explorer.keymaps.go_up"))

  -- Verify we're back in root
  assert_equal(find_line_in_explorer("Program Files$").found, true)
end

T["navigation"]["should_open_files_in_appropriate_window"] = function()
  local test_dir = create_test_dir()

  -- Create initial split and open explorer
  child.cmd("vsplit")
  open_explorer_with(test_dir)
  assert_equal(#child.api.nvim_list_wins(), 3, "Should have three windows")

  local win = child.lua_get("w.explorer.get_window()")
  local result = find_line_in_explorer("测试文件.md$")

  child.api.nvim_win_set_cursor(win, { result.index, 0 })
  child.type_keys(child.lua_get("w.config.options.explorer.keymaps.open"))

  -- Verify file opened correctly
  local expected_path = child.fn.resolve(test_dir .. "/测试文件.md")
  local actual_path =
    child.fn.fnamemodify(child.api.nvim_buf_get_name(child.api.nvim_get_current_buf()), ":p")
  assert_equal(actual_path, expected_path)
end

T["navigation"]["should_handle_invalid_directory"] = function()
  local invalid_dir = "/path/that/does/not/exist"
  open_explorer_with(invalid_dir)

  assert_equal(child.lua_get("w.explorer.get_window()"), vim.NIL)
end

-- Test file highlighting
T["highlighting"] = new_set()

T["highlighting"]["should_highlight_current_file"] = function()
  local test_dir = create_test_dir()
  local file_path = test_dir .. "/file1.txt"
  open_explorer_with(vim.fn.fnamemodify(file_path, ":h"))

  child.cmd("wincmd l | edit " .. file_path)

  -- Check highlighting
  local has_highlight = child.lua([[
    local buf = w.explorer.get_buffer()
    local ns = vim.api.nvim_create_namespace(w.config.const.namespace)
    
    local extmarks = vim.api.nvim_buf_get_extmarks(
      buf,
      ns,
      { 0, 0 },
      { -1, -1 },
      { details = true }
    )

    for _, mark in ipairs(extmarks) do
      if mark[4].hl_group == "CursorLine" then
        return true
      end
    end
    return false
  ]])
  assert_equal(has_highlight, true)
end

return T
