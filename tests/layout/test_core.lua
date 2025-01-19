-- tests/test_layout_core.lua
local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal

-- Create child process with required modules
local child, hooks = H.new_child({ "layout", "layout.core" })

-- Create test set with hooks
local T = new_set({ hooks = hooks })

-- Helper functions
local function create_basic_split()
  -- Creates basic A|B split and returns window handles
  child.lua('w.layout.split("right")')
  return child.lua([[
    local tree = vim.fn.winlayout()
    return {
      A = tree[2][1][2],
      B = tree[2][2][2]
    }
  ]])
end

local function create_complex_split()
  -- Creates A|B/C split and returns window handles
  child.lua('w.layout.split("right")')
  child.lua('w.layout.split("down")')
  return child.lua([[
    local tree = vim.fn.winlayout()
    return {
      A = tree[2][1][2],
      B = tree[2][2][2][1][2],
      C = tree[2][2][2][2][2]
    }
  ]])
end

-- Test find_target_window
T["find_target_window"] = new_set()

T["find_target_window"]["should_find_existing_window_in_simple_split"] = function()
  local wins = create_basic_split()

  -- Test finding window from A to B
  child.api.nvim_set_current_win(wins.A)
  local target = child.lua_get("w.layout.core.find_target_window(...)", { wins.A, "right" })
  assert_equal(target, wins.B)

  -- Test finding window from B to A
  child.api.nvim_set_current_win(wins.B)
  target = child.lua_get("w.layout.core.find_target_window(...)", { wins.B, "left" })
  assert_equal(target, wins.A)
end

T["find_target_window"]["should_handle_non_existent_directions"] = function()
  local wins = create_basic_split()

  -- Test invalid directions from A
  child.api.nvim_set_current_win(wins.A)
  local target = child.lua_get("w.layout.core.find_target_window(...)", { wins.A, "up" })
  assert_equal(target, vim.NIL)

  target = child.lua_get("w.layout.core.find_target_window(...)", { wins.A, "down" })
  assert_equal(target, vim.NIL)
end

T["find_target_window"]["should_work_with_complex_layouts"] = function()
  local wins = create_complex_split()

  -- Test vertical navigation
  child.api.nvim_set_current_win(wins.B)
  local target = child.lua_get("w.layout.core.find_target_window(...)", { wins.B, "down" })
  assert_equal(target, wins.C)

  child.api.nvim_set_current_win(wins.C)
  target = child.lua_get("w.layout.core.find_target_window(...)", { wins.C, "up" })
  assert_equal(target, wins.B)
end

-- Test can_split
T["can_split"] = new_set()

T["can_split"]["should_allow_first_split"] = function()
  local result = child.lua_get('w.layout.core.can_split(vim.api.nvim_get_current_win(), "right")')
  assert_equal(result, true)
end

T["can_split"]["should_prevent_third_horizontal_split"] = function()
  local wins = create_basic_split()

  child.api.nvim_set_current_win(wins.B)
  local result = child.lua_get('w.layout.core.can_split(vim.api.nvim_get_current_win(), "right")')
  assert_equal(result, false)
end

T["can_split"]["should_allow_nested_splits_in_different_directions"] = function()
  local wins = create_basic_split()

  child.api.nvim_set_current_win(wins.B)
  local result = child.lua_get('w.layout.core.can_split(vim.api.nvim_get_current_win(), "down")')
  assert_equal(result, true)
end

T["can_split"]["should_prevent_third_vertical_split"] = function()
  -- Create two vertical splits first
  child.lua('w.layout.split("down")')
  child.lua('w.layout.split("down")')

  -- Try to create a third vertical split
  local result = child.lua_get('w.layout.core.can_split(vim.api.nvim_get_current_win(), "down")')
  assert_equal(result, false)
end

return T
