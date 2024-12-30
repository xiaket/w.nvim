-- tests/test_layout.lua
local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal
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
  local wins = child.lua([[
    local wins = vim.api.nvim_list_wins()
    return wins
  ]])
  assert_equal(#wins, 2)

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
  local wins = child.lua([[
    local wins = vim.api.nvim_list_wins()
    return wins
  ]])
  assert_equal(#wins, 2)

  -- Split down on bottom split should be no-op
  child.api.nvim_set_current_win(wins[2])
  child.lua('w.layout.split("down")')
  window.assert_count(child, 2)

  -- Split up on top split should be no-op
  child.api.nvim_set_current_win(wins[1])
  child.lua('w.layout.split("up")')
  window.assert_count(child, 2)
end

T["split"]["should_handle_three_splits_operations"] = function()
  -- Create initial A|B split
  child.lua('w.layout.split("right")')
  window.assert_count(child, 2)

  -- Create B/C split
  child.lua('w.layout.split("down")')
  local wins = child.lua([[
    local tree = vim.fn.winlayout()
    -- { "row", { { "leaf", A }, { "col", { { "leaf", B }, { "leaf", C } } } } }
    local win_A = tree[2][1][2]  
    local win_B = tree[2][2][2][1][2]
    local win_C = tree[2][2][2][2][2]
    return { win_A = win_A, win_B = win_B, win_C = win_C }
  ]])
  window.assert_count(child, 3)

  -- Test window navigation
  -- Run split left on B should land on A
  child.api.nvim_set_current_win(wins.win_B)
  child.lua('w.layout.split("left")')
  window.expect_count_and_pos(child, 3, wins.win_A)

  -- We are in A, to back to C
  child.api.nvim_set_current_win(wins.win_C)
  -- Run split left on C should land on A
  child.lua('w.layout.split("left")')
  window.expect_count_and_pos(child, 3, wins.win_A)

  -- Run split right on A should land on C as it's last active
  child.lua('w.layout.split("right")')
  window.expect_count_and_pos(child, 3, wins.win_C)

  -- Run split up on C should land on B
  child.lua('w.layout.split("up")')
  window.expect_count_and_pos(child, 3, wins.win_B)
end

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

  local wins = child.lua([[
    local tree = vim.fn.winlayout()
    -- { "row", { { "leaf", A }, { "col", { { "leaf", B }, { "row", { { "leaf", C }, { "leaf", D } } } } } } }
    local win_A = tree[2][1][2]  
    local win_B = tree[2][2][2][1][2]
    local win_C = tree[2][2][2][2][2][1][2]
    local win_D = tree[2][2][2][2][2][2][2]
    return { win_A = win_A, win_B = win_B, win_C = win_C, win_D = win_D }
  ]])
  window.expect_count_and_pos(child, 4, wins.win_D)

  -- Split left in D should land in C
  child.lua('w.layout.split("left")')
  window.expect_count_and_pos(child, 4, wins.win_C)

  -- Split left in C should land in A
  child.lua('w.layout.split("left")')
  window.expect_count_and_pos(child, 4, wins.win_A)

  -- Split right in A should land in C, as it's last active
  child.lua('w.layout.split("right")')
  window.expect_count_and_pos(child, 4, wins.win_C)

  -- Split up should land in B
  child.lua('w.layout.split("up")')
  window.expect_count_and_pos(child, 4, wins.win_B)
end

-- Testing navigation
T["navigation"] = new_set()

T["navigation"]["should_find_adjacent_window"] = function()
  -- Create vsplit using native command
  child.cmd("vsplit")

  -- Verify we have two windows
  local wins = child.lua([[
    local wins = vim.api.nvim_list_wins()
    return wins
  ]])
  assert_equal(#wins, 2)

  -- Verify layout - second window should be on the right
  local has_right = child.lua([[
    local wins = vim.api.nvim_list_wins()
    return vim.api.nvim_win_get_position(wins[2])[2] > 0
  ]])
  assert_equal(has_right, true)
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
  local width_diff = math.abs(sizes.win_B.width - expected_width)
  assert_equal(width_diff <= 1, true)

  -- Window A should get remaining space
  local remaining_width = sizes.total_width - sizes.win_B.width
  local a_width_diff = math.abs(sizes.win_A.width - remaining_width)
  assert_equal(a_width_diff <= 1, true)
end

T["calculate_window_sizes"]["handles_nested_splits"] = function()
  -- Create A|B split first
  child.lua('w.layout.split("right")')

  -- Focus B and create B/C split
  child.lua([[
    local wins = vim.api.nvim_list_wins()
    vim.api.nvim_set_current_win(wins[2]) 
    w.layout.split("down")
  ]])

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
  local a_width_diff = math.abs(a_width - expected_a_width)
  assert_equal(a_width_diff <= 1, true)

  -- B and C should split right side
  assert_equal(data.sizes[data.win_B].width, data.sizes[data.win_C].width)

  -- C (active) should get golden ratio of height
  local c_height = data.sizes[data.win_C].height
  local expected_c_height = math.floor(data.total_height * data.split_ratio)
  local c_height_diff = math.abs(c_height - expected_c_height)
  assert_equal(c_height_diff <= 1, true)

  -- B should get remaining height
  local b_height = data.sizes[data.win_B].height
  local remaining_height = data.total_height - c_height
  local b_height_diff = math.abs(b_height - remaining_height)
  assert_equal(b_height_diff <= 1, true)
end

-- Test explorer window handling
T["calculate_window_sizes"]["handles explorer window"] = function()
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
  local width_diff = math.abs(sizes.explorer_width - sizes.config_width)
  assert_equal(width_diff <= 1, true)
end

return T
