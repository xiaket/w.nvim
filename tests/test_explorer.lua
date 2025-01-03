-- tests/test_explorer.lua
local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal
local assert_almost_equal = H.assert_almost_equal

-- Create child process with required modules
local child, hooks = H.new_child({ "init", "config", "layout", "explorer" })

-- Create test set with hooks
local T = new_set({ hooks = hooks })

-- Helper functions for test directory management
local function ensure_clean_dir(dir)
  child.lua(
    [[
    local dir = ...
    -- Try to delete first if exists
    if vim.fn.isdirectory(dir) == 1 then
      vim.fn.delete(dir, "rf")
    end
    -- Create fresh directory
    vim.fn.mkdir(dir, "p")
  ]],
    { dir }
  )
end

local get_key = function(path)
  local keys = child.lua_get(path)
  if type(keys) == "table" then
    return keys[1]
  else
    return keys
  end
end

local function create_test_dir()
  local test_dir = child.lua_get("vim.fn.tempname()")

  ensure_clean_dir(test_dir)

  child.lua(
    [[
    local test_dir = ...
    local files = {
      "normal.file",
      "file1.txt",
      "file2.lua",
      ".hidden_file",
      "test_dir/nested_file.txt",
      "empty_dir/",
    }

    for _, file in ipairs(files) do
      if file:match("/$") then
        vim.fn.mkdir(test_dir .. "/" .. file:sub(1, -2), "p")
      else
        local dir = file:match("(.+)/")
        if dir then
          vim.fn.mkdir(test_dir .. "/" .. dir, "p")
        end
        local f = io.open(test_dir .. "/" .. file, "w")
        if f then
          f:write("Test content")
          f:close()
        end
      end
    end
  ]],
    { test_dir }
  )

  return test_dir
end

-- Cleanup helper
local function cleanup_test_dir(dir)
  if not dir then
    return
  end
  -- TODO: make this shorter.
  child.lua(
    [[
    local dir = ...
    if vim.fn.isdirectory(dir) == 1 then
      vim.fn.delete(dir, "rf")
    end
  ]],
    { dir }
  )
end

-- Test explorer toggle functionality
T["toggle_explorer"] = new_set()

T["toggle_explorer"]["should_create_and_close_explorer_window"] = function()
  local wins_before = child.lua_get("#vim.api.nvim_list_wins()")
  assert_equal(wins_before, 1, "Should start with exactly one window")

  -- Toggle explorer on
  child.lua([[w.explorer.open()]])
  local wins = child.lua_get("#vim.api.nvim_list_wins()")
  assert_equal(wins, 2, "Should have two windows after open")

  -- Verify explorer window properties
  local explorer_info = child.lua([[
    local win = w.explorer.get_state().window
    return win and {
      width = vim.api.nvim_win_get_width(win)
    }
  ]])

  assert_equal(explorer_info ~= nil, true)
  assert_almost_equal(explorer_info.width, child.lua_get("w.config.options.explorer.window_width"))

  -- Toggle explorer off
  child.lua([[w.explorer.close()]])
  wins = child.lua_get("#vim.api.nvim_list_wins()")
  assert_equal(wins, wins_before)
end

-- Test directory reading and display
T["directory_reading"] = new_set()

T["directory_reading"]["should_respect_show_hidden_setting"] = new_set({
  parametrize = {
    { true }, -- show_hidden = true
    { false }, -- show_hidden = false
  },
})

T["directory_reading"]["should_respect_show_hidden_setting"]["works"] = function(show_hidden)
  local test_dir = create_test_dir()

  -- Setup config with parametrized value
  child.lua(
    [[
  w.config.setup({ explorer = {show_hidden = select(1, ...) }})
  w.explorer.open(select(2, ...))
    ]],
    { show_hidden, test_dir }
  )

  -- Check results
  local results = child.lua([[
    local buf = w.explorer.get_state().buffer
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local has_hidden, has_normal, has_dir = false, false, false
    for _, line in ipairs(lines) do
      if line:match("%.hidden_file$") then has_hidden = true end
      if line:match("normal.file$") then has_normal = true end
      if line:match("test_dir$") then has_dir = true end
    end
    return { has_hidden = has_hidden, has_normal = has_normal, has_dir = has_dir }
  ]])

  -- Expectations should match the show_hidden parameter
  assert_equal(results.has_hidden, show_hidden)
  assert_equal(results.has_normal, true) -- normal files always shown
  assert_equal(results.has_dir, true) -- directories always shown

  cleanup_test_dir(test_dir)
end

T["directory_reading"]["should_respect_max_files_setting"] = function()
  local test_dir = create_test_dir()

  -- Test with max_files = 100
  child.lua(
    [[
    w.config.setup({ explorer = {max_files = 3 }})
    w.explorer.open(...)
  ]],
    { test_dir }
  )

  local file_info = child.lua([[
    local buf = w.explorer.get_state().buffer
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return {
      truncation_message = lines[#lines] == "['j' to load more]",
      line_count = #lines
    }
  ]])
  assert_equal(file_info.truncation_message, true)
  assert_equal(file_info.line_count <= 100, true)

  cleanup_test_dir(test_dir)
end

-- Test navigation functionality
T["navigation"] = new_set()

T["navigation"]["should_navigate_directories"] = function()
  local test_dir = create_test_dir()

  -- Set up explorer
  child.lua([[w.explorer.open(...)]], { test_dir })

  -- Find and enter test_dir
  local test_dir_line = child.lua([[
    local buf = w.explorer.get_state().buffer
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("test_dir$") then
        return i
      end
    end
  ]])
  assert_equal(test_dir_line ~= nil, true)

  -- Navigate to test_dir and open it
  child.lua(
    [[    vim.api.nvim_win_set_cursor(w.explorer.get_state().window, {...})]],
    { test_dir_line, 0 }
  )

  child.type_keys(get_key("w.config.options.explorer.keymaps.open"))

  -- Verify we can see nested_file.txt
  local has_nested = child.lua([[
    local buf = w.explorer.get_state().buffer
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:match("nested_file.txt$") then
        return true
      end
    end
    return false
  ]])
  assert_equal(has_nested, true)

  -- Test going up
  child.type_keys(get_key("w.config.options.explorer.keymaps.go_up"))

  -- Verify we're back in root
  local has_test_dir = child.lua([[
    local buf = w.explorer.get_state().buffer
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:match("test_dir$") then
        return true
      end
    end
    return false
  ]])
  assert_equal(has_test_dir, true)

  cleanup_test_dir(test_dir)
end

T["navigation"]["should_open_files_in_appropriate_window"] = function()
  local test_dir = create_test_dir()

  -- Create initial split and open explorer
  child.cmd("vsplit")
  local wins_before = child.lua_get("#vim.api.nvim_list_wins()")
  child.lua([[w.explorer.open(...)]], { test_dir })

  -- Find and open file1.txt
  local file_line = child.lua([[
    local buf = w.explorer.get_state().buffer
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("file1.txt$") then
        return i
      end
    end
  ]])

  child.lua([[vim.api.nvim_win_set_cursor(w.explorer.get_state().window, {...})]], { file_line, 0 })
  child.type_keys(child.lua_get("w.config.options.explorer.keymaps.open"))

  -- Verify file opened correctly
  local result = child.lua(
    [[
    local vresult = vim.fn.win_getid(vim.fn.bufwinnr(...))
    local test_dir = ...
    local current_buf = vim.api.nvim_get_current_buf()
    local buf_name = vim.api.nvim_buf_get_name(current_buf)
    return {
      expected_path = vim.fn.resolve(test_dir .. "/file1.txt"),
      actual_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(current_buf), ":p"),
      win_count = #vim.api.nvim_list_wins()
    }
  ]],
    { test_dir }
  )

  assert_equal(result.actual_path, result.expected_path)
  assert_equal(result.win_count, wins_before + 1) -- +1 for explorer

  cleanup_test_dir(test_dir)
end

-- Test file highlighting
T["highlighting"] = new_set()

T["highlighting"]["should_highlight_current_file"] = function()
  local test_dir = create_test_dir()
  local file_path = test_dir .. "/file1.txt"

  child.lua(
    [[
    vim.cmd("edit " .. ...)
    w.explorer.get_state().current_file = ...
    w.explorer.open(vim.fn.fnamemodify(..., ":h"))
  ]],
    { file_path }
  )

  -- Check highlighting
  local has_highlight = child.lua([[
    local buf = w.explorer.get_state().buffer
    local ns = vim.api.nvim_create_namespace('explorer_highlight')
    
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

  cleanup_test_dir(test_dir)
end

return T
