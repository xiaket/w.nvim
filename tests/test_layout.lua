-- tests/test_layout.lua
local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal
local assert_almost_equal = H.assert_almost_equal
local window = H.window

-- Create child process with required modules
local child, hooks = H.new_child({ "init", "config", "layout", "explorer" })

-- Create test set with hooks
local T = new_set({ hooks = hooks })

-- Testing split logic
T["split"] = new_set()

T["split"]["native_split_still_works"] = function()
  local wins_before = window.get_count(child)
  child.cmd("split") -- Native split should still work
  window.assert_count(child, wins_before + 1)
  child.cmd("vsplit") -- Native split bypass our split logic
  window.assert_count(child, wins_before + 2)
end

T["split"]["should_prevent_invalid_horizontal_splits"] = function()
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

T["split"]["should_prevent_invalid_vertical_splits"] = function()
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
T["split"]["should_handle_three_splits_operations"] = function()
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
T["split"]["should_handle_complex_split_operations"] = function()
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

-- Test window sizes calculation
T["calculate_window_sizes"] = new_set()

T["calculate_window_sizes"]["handles_basic_horizontal_split"] = function()
  -- Create A|B layout
  child.lua('w.layout.split("right")')
  local sizes = child.lua([[
    local wins = vim.api.nvim_list_wins()
    local win_A, win_B = wins[1], wins[2]
    local total_width = vim.o.columns
    
    local sizes = w.layout.calculate_window_sizes()
    return {
      win_A = { width = sizes[win_A].width },
      win_B = { width = sizes[win_B].width },
      total_width = total_width,
      split_ratio = w.config.options.split_ratio
    }
  ]])

  -- Active window (B) should get golden ratio
  local expected_width = math.floor(sizes.total_width * sizes.split_ratio)
  assert_almost_equal(sizes.win_B.width, expected_width)

  -- Window A should get remaining space
  local remaining_width = sizes.total_width - sizes.win_B.width
  assert_almost_equal(sizes.win_A.width, remaining_width)
end

T["calculate_window_sizes"]["handles_nested_splits"] = function()
  -- Create A|B split first
  child.lua('w.layout.split("right")')
  -- Focus B and create B/C split
  child.lua('w.layout.split("down")')

  -- Get window IDs and sizes
  local data = child.lua([[
    local tree = vim.fn.winlayout()
    local win_A = tree[2][1][2]
    local win_B = tree[2][2][2][1][2] 
    local win_C = tree[2][2][2][2][2]
    
    -- Focus C as active window
    vim.api.nvim_set_current_win(win_C)
    
    local total_width = vim.o.columns
    local total_height = vim.o.lines
    local sizes = w.layout.calculate_window_sizes()
    
    return {
      sizes = sizes,
      win_A = win_A,
      win_B = win_B, 
      win_C = win_C,
      total_width = total_width,
      total_height = total_height,
      split_ratio = w.config.options.split_ratio
    }
  ]])

  -- A should take left side
  local a_width = data.sizes[data.win_A].width
  local expected_a_width = math.floor(data.total_width * (1 - data.split_ratio))
  assert_almost_equal(a_width, expected_a_width)

  -- B and C should split right side
  assert_equal(data.sizes[data.win_B].width, data.sizes[data.win_C].width)

  -- C (active) should get golden ratio of height
  local c_height = data.sizes[data.win_C].height
  local expected_c_height = math.floor(data.total_height * data.split_ratio)
  assert_almost_equal(c_height, expected_c_height)

  -- B should get remaining height
  local b_height = data.sizes[data.win_B].height
  local remaining_height = data.total_height - c_height
  assert_almost_equal(b_height, remaining_height)
end

-- Test explorer window handling
T["calculate_window_sizes"]["handles_explorer_window"] = function()
  -- Setup explorer window
  child.lua("w.explorer.toggle_explorer()")

  -- Create another window
  child.lua('w.layout.split("right")')
  -- switch back to explorer
  child.lua('w.layout.split("left")')

  -- Check sizes
  local sizes = child.lua([[
    local wins = vim.api.nvim_list_wins()
    local current = vim.api.nvim_get_current_win()
    local sizes = w.layout.calculate_window_sizes()
    return {
      explorer_width = sizes[current].width,
      config_width = w.config.options.explorer_window_width
    }
  ]])

  -- Explorer should have fixed width
  assert_almost_equal(sizes.explorer_width, sizes.config_width)
end

-- Test explorer window handling
T["calculate_window_sizes"]["handles_explorer_window_with_horizontal_split"] = function()
  -- Create A|B split first
  child.lua('w.layout.split("right")')
  -- Open explorer window
  child.lua("w.explorer.toggle_explorer()")

  -- Get all window sizes
  local data = child.lua([=[
    local wins = vim.api.nvim_list_wins()
    local explorer_win, other_wins = nil, {}
    local debug = require("w.debug")
    
    -- Identify explorer and other windows
    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_option(buf, "filetype") == w.layout.EXPLORER_FILETYPE then
        explorer_win = win
      else
        table.insert(other_wins, win)
      end
    end
    
    -- Get size data
    local sizes = w.layout.calculate_window_sizes()
    debug.log("sizes:", vim.inspect(sizes))
    debug.log("explorer_win:", explorer_win)
    return {
      explorer_width = sizes[explorer_win].width,
      config_width = w.config.options.explorer_window_width,
      other_sizes = {
        first = { width = sizes[other_wins[1]].width },
        second = { width = sizes[other_wins[2]].width }
      }
    }
  ]=])

  -- Explorer should have fixed width
  assert_almost_equal(data.explorer_width, data.config_width)

  -- Other windows should split remaining space according to golden ratio
  local total_width = data.other_sizes.first.width + data.other_sizes.second.width
  local expected_second_width =
    math.floor(total_width * child.lua_get("w.config.options.split_ratio"))
  assert_almost_equal(data.other_sizes.second.width, expected_second_width)
end

T["calculate_window_sizes"]["handles_explorer_window_with_vertical_split"] = function()
  -- Create A/B split first
  child.lua('w.layout.split("down")')

  -- Open explorer window
  child.lua("w.explorer.toggle_explorer()")

  -- Get all window sizes
  local data = child.lua([=[
    local wins = vim.api.nvim_list_wins()
    local explorer_win, other_wins = nil, {}
    
    -- Identify explorer and other windows
    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_option(buf, "filetype") == w.layout.EXPLORER_FILETYPE then
        explorer_win = win
      else
        table.insert(other_wins, win)
      end
    end
    
    -- Get size data
    local sizes = w.layout.calculate_window_sizes()
    return {
      explorer_width = sizes[explorer_win].width,
      config_width = w.config.options.explorer_window_width,
      other_sizes = {
        first = { 
          width = sizes[other_wins[1]].width,
          height = sizes[other_wins[1]].height 
        },
        second = { 
          width = sizes[other_wins[2]].width,
          height = sizes[other_wins[2]].height 
        }
      }
    }
  ]=])

  -- Explorer should have fixed width
  assert_almost_equal(data.explorer_width, data.config_width)

  -- Other windows should keep the same width after explorer opens
  assert_equal(data.other_sizes.first.width, data.other_sizes.second.width)

  -- Verify vertical split still follows golden ratio
  local total_height = data.other_sizes.first.height + data.other_sizes.second.height
  local expected_second_height =
    math.floor(total_height * child.lua_get("w.config.options.split_ratio"))
  assert_almost_equal(data.other_sizes.second.height, expected_second_height)
end

return T
