local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal

local child, hooks = H.new_child({ "explorer", "explorer.actions" })
local T = new_set({ hooks = hooks })

-- Helper to create test directory with files
local function create_test_dir()
  local dir = child.lua_get("vim.fn.tempname()")
  child.lua(
    [[
    local dir = ...
    -- Create test directory and files
    vim.fn.mkdir(dir, "p")
    local f1 = io.open(dir .. "/file1.txt", "w")
    f1:write("test1")
    f1:close()
    local f2 = io.open(dir .. "/file2.txt", "w")
    f2:write("test2")
    f2:close()
    return dir
  ]],
    { dir }
  )
  return dir
end

T["find_window_for_file"] = new_set()

T["find_window_for_file"]["should_handle_invalid_previous_window"] = function()
  local test_dir = create_test_dir()

  -- Setup explorer and open file1
  child.lua(
    [[
    local dir = ...
    local explorer = require('w.explorer')
    explorer.open(dir)
  ]],
    { test_dir }
  )

  -- Navigate to file1.txt and open it
  child.lua([[
    local actions = require('w.explorer.actions')
    actions.open_current()
  ]])

  -- Close the file window (making previous_active_window invalid)
  child.cmd("quit")

  -- Try to open another file - we should get a valid window despite previous window being invalid
  child.lua([[
    local actions = require('w.explorer.actions')
    local win = actions.find_window_for_file(require('w.explorer').get_window())
    return win ~= nil and vim.api.nvim_win_is_valid(win)
  ]])

  -- Assert that we got a valid window despite previous window being invalid
  assert_equal(child.lua_get("#vim.api.nvim_list_wins()"), 2)
end

return T
