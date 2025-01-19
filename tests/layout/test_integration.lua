-- tests/test_layout_integration.lua
local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal
local window = H.window

-- Create child process with required modules
local child, hooks = H.new_child({ "config", "layout" })

-- Create test set with hooks
local T = new_set({ hooks = hooks })

-- Testing layout integration
T["layout"] = new_set()

T["layout"]["should_allow_native_splits_to_work"] = function()
  local wins_before = window.get_count(child)
  child.cmd("split") -- Native split should still work
  window.assert_count(child, wins_before + 1)
  child.cmd("vsplit") -- Native split bypass our split logic
  window.assert_count(child, wins_before + 2)
end

T["layout"]["should_prevent_invalid_horizontal_splits"] = function()
  -- Create a split on the right
  child.lua('w.layout.split("right")')
  local wins = child.lua_get("vim.api.nvim_list_wins()")
  window.assert_count(child, 2)

  -- Split right on right split should be no-op
  child.api.nvim_set_current_win(wins[2])
  child.lua('w.layout.split("right")')
  window.assert_count(child, 2)

  -- Split left on left split should be no-op
  child.api.nvim_set_current_win(wins[1])
  child.lua('w.layout.split("left")')
  window.assert_count(child, 2)
end

T["layout"]["should_prevent_invalid_vertical_splits"] = function()
  -- Create a split down
  child.lua('w.layout.split("down")')
  local wins = child.lua_get("vim.api.nvim_list_wins()")
  window.assert_count(child, 2)

  -- Split down on bottom split should be no-op
  child.api.nvim_set_current_win(wins[2])
  child.lua('w.layout.split("down")')
  window.assert_count(child, 2)

  -- Split up on top split should be no-op
  child.api.nvim_set_current_win(wins[1])
  child.lua('w.layout.split("up")')
  window.assert_count(child, 2)
end

-- +---+---+     +------+------+
-- |   | B |     |      | 1002 |
-- | A +---+  -> | 1001 +------+
-- |   | C |     |      | 1000 |
-- +---+---+     +------+------+
T["layout"]["should_handle_three_splits_operations"] = function()
  -- Create initial A|B split
  child.lua('w.layout.split("right")')
  window.assert_count(child, 2)

  -- Create B/C split
  child.lua('w.layout.split("down")')
  window.assert_count(child, 3)

  -- We should see the following win ids.
  local win = child.lua([[
    local tree = vim.fn.winlayout()
    -- { "row", { { "leaf", A }, { "col", { { "leaf", B }, { "leaf", C } } } } }
    local win_A = tree[2][1][2]
    local win_B = tree[2][2][2][1][2]
    local win_C = tree[2][2][2][2][2]
    return { A = win_A, B = win_B, C = win_C }
  ]])
  assert_equal(win.A, 1001)
  assert_equal(win.B, 1002)
  assert_equal(win.C, 1000)

  -- Test window navigation
  -- Run split left on B should land on A
  child.api.nvim_set_current_win(win.B)
  child.lua('w.layout.split("left")')
  window.expect_count_and_pos(child, 3, win.A)

  -- We are in A, to back to C
  child.api.nvim_set_current_win(win.C)
  -- Run split left on C should land on A
  child.lua('w.layout.split("left")')
  window.expect_count_and_pos(child, 3, win.A)

  -- Run split right on A should land on C as it's last active
  child.lua('w.layout.split("right")')
  window.expect_count_and_pos(child, 3, win.C)

  -- Run split up on C should land on B
  child.lua('w.layout.split("up")')
  window.expect_count_and_pos(child, 3, win.B)
end

-- +---+---+---+     +------+-------------+
-- |   |   B   |     |      |     1002    |
-- | A +---+---+  -> | 1001 +------+------+
-- |   | C | D |     |      | 1003 | 1000 |
-- +---+---+---+     +------+-------------+
T["layout"]["should_handle_complex_split_operations"] = function()
  -- Create initial A|B split
  child.lua('w.layout.split("right")')
  window.assert_count(child, 2)

  -- Create B/C split
  child.lua('w.layout.split("down")')
  window.assert_count(child, 3)

  -- Do split Down in C before creating D, should be no-op
  child.lua('w.layout.split("down")')
  window.assert_count(child, 3)

  -- Creating D
  child.lua('w.layout.split("right")')
  window.assert_count(child, 4)

  local win = child.lua([[
    local tree = vim.fn.winlayout()
    -- { "row", { { "leaf", A }, { "col", { { "leaf", B }, { "row", { { "leaf", C }, { "leaf", D } } } } } } }
    local win_A = tree[2][1][2]  
    local win_B = tree[2][2][2][1][2]
    local win_C = tree[2][2][2][2][2][1][2]
    local win_D = tree[2][2][2][2][2][2][2]
    return { A = win_A, B = win_B, C = win_C, D = win_D }
  ]])
  assert_equal(win.A, 1001)
  assert_equal(win.B, 1002)
  assert_equal(win.C, 1003)
  assert_equal(win.D, 1000)
  window.expect_count_and_pos(child, 4, win.D)

  -- Test window navigation sequence
  -- Split left in D should land in C
  child.lua('w.layout.split("left")')
  window.expect_count_and_pos(child, 4, win.C)

  -- Split left in C should land in A
  child.lua('w.layout.split("left")')
  window.expect_count_and_pos(child, 4, win.A)

  -- Split right in A should land in C, as it's last active
  child.lua('w.layout.split("right")')
  window.expect_count_and_pos(child, 4, win.C)

  -- Split up should land in B
  child.lua('w.layout.split("up")')
  window.expect_count_and_pos(child, 4, win.B)
end

T["layout"]["should_handle_window_resize_after_split"] = function()
  local width_before = child.lua_get("vim.api.nvim_win_get_width(0)")

  -- Create right split
  child.lua('w.layout.split("right")')
  local width_after = child.lua_get("vim.api.nvim_win_get_width(0)")

  -- Get split ratio from config
  local split_ratio = child.lua_get("w.config.options.split_ratio")

  -- Should be roughly split according to config ratio
  local ratio = width_after / width_before
  H.assert_almost_equal(ratio, 1 - split_ratio)
end

return T
