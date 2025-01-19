-- tests/test_layout_util.lua
local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal

-- Create child process with required modules
local child, hooks = H.new_child({ "config", "explorer", "layout", "layout.util" })

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

-- Test find_window_in_tree
T["find_window_in_tree"] = new_set()

T["find_window_in_tree"]["should_find_window_and_parent_in_simple_layout"] = function()
  local wins = create_basic_split()

  local result = child.lua(
    [[
    local tree = vim.fn.winlayout()
    local win_id = ...
    local found, parent = w.layout.util.find_window_in_tree(tree, win_id)
    return { found = found[2], parent = parent and parent[1] }
  ]],
    { wins.A }
  )

  assert_equal(result.found, wins.A)
  assert_equal(result.parent, "row")
end

T["find_window_in_tree"]["should_handle_invalid_window_ids"] = function()
  create_basic_split()

  local result = child.lua([[
    local tree = vim.fn.winlayout()
    local found, parent = w.layout.util.find_window_in_tree(tree, 99999)
    return { found = found, parent = parent }
  ]])

  assert_equal(result.found, nil)
  assert_equal(result.parent, nil)
end

T["find_window_in_tree"]["should_find_window_in_complex_layout"] = function()
  local wins = create_complex_split()

  local result = child.lua(
    [[
    local tree = vim.fn.winlayout()
    local win_id = ...
    local found, parent = w.layout.util.find_window_in_tree(tree, win_id)
    return { found = found[2], parent_type = parent and parent[1] }
  ]],
    { wins.C }
  )

  assert_equal(result.found, wins.C)
  assert_equal(result.parent_type, "col")
end

-- Test find_path_to_window
T["find_path_to_window"] = new_set()

T["find_path_to_window"]["should_find_path_in_simple_layout"] = function()
  local wins = create_basic_split()

  local path = child.lua(
    [[
    local tree = vim.fn.winlayout()
    return w.layout.util.find_path_to_window(tree, ..., {})
  ]],
    { wins.B }
  )

  assert_equal(#path, 1)
  assert_equal(path[1].index, 2)
end

T["find_path_to_window"]["should_find_path_in_complex_layout"] = function()
  local wins = create_complex_split()

  local path = child.lua(
    [[
    local tree = vim.fn.winlayout()
    return w.layout.util.find_path_to_window(tree, ..., {})
  ]],
    { wins.C }
  )

  assert_equal(#path, 2)
  assert_equal(path[1].index, 2) -- Second split in root
  assert_equal(path[2].index, 2) -- Second split in vertical split
end

T["find_path_to_window"]["should_handle_invalid_window_id"] = function()
  create_basic_split()

  local path = child.lua([[
    local tree = vim.fn.winlayout()
    return w.layout.util.find_path_to_window(tree, 99999, {})
  ]])

  assert_equal(path, vim.NIL)
end

-- Test get_relative_direction
T["get_relative_direction"] = new_set()

T["get_relative_direction"]["should_determine_horizontal_directions"] = function()
  local wins = create_basic_split()

  local direction = child.lua(
    [[
    return w.layout.util.get_relative_direction(...)
  ]],
    { wins.A, wins.B }
  )
  assert_equal(direction, "right")

  direction = child.lua(
    [[
    return w.layout.util.get_relative_direction(...)
  ]],
    { wins.B, wins.A }
  )
  assert_equal(direction, "left")
end

T["get_relative_direction"]["should_determine_vertical_directions"] = function()
  local wins = create_complex_split()

  local direction = child.lua(
    [[
    return w.layout.util.get_relative_direction(...)
  ]],
    { wins.B, wins.C }
  )
  assert_equal(direction, "down")

  direction = child.lua(
    [[
    return w.layout.util.get_relative_direction(...)
  ]],
    { wins.C, wins.B }
  )
  assert_equal(direction, "up")
end

T["get_relative_direction"]["should_handle_unrelated_windows"] = function()
  -- Create two separate splits
  child.cmd("split")
  child.cmd("vsplit")
  local unrelated_win = child.api.nvim_get_current_win()
  child.cmd("close")

  -- Create normal split
  local wins = create_basic_split()

  local direction = child.lua(
    [[
    return w.layout.util.get_relative_direction(...)
  ]],
    { wins.A, unrelated_win }
  )
  assert_equal(direction, vim.NIL)
end

T["get_relative_direction"]["should_handle_invalid_window_ids"] = function()
  local wins = create_basic_split()

  local direction = child.lua(
    [[
    return w.layout.util.get_relative_direction(...)
  ]],
    { wins.A, 99999 }
  )
  assert_equal(direction, vim.NIL)

  direction = child.lua(
    [[
    return w.layout.util.get_relative_direction(...)
  ]],
    { 99999, wins.A }
  )
  assert_equal(direction, vim.NIL)
end

-- Test get_dimensional_parent
T["get_dimensional_parent"] = new_set()

T["get_dimensional_parent"]["returns_nil_for_invalid_window"] = function()
  -- Set up some split layout first
  child.lua('w.layout.split("right")')
  local result = child.lua([[
    local invalid_win = 9999
    return w.layout.util.get_dimensional_parent(vim.fn.winlayout(), invalid_win, true)
  ]])
  assert_equal(result, vim.NIL)
end

T["get_dimensional_parent"]["returns_nil_for_single_window"] = function()
  local result = child.lua([[
    local current_win = vim.api.nvim_get_current_win()
    return w.layout.util.get_dimensional_parent(vim.fn.winlayout(), current_win, true)
  ]])
  assert_equal(result, vim.NIL)
end

T["get_dimensional_parent"]["finds_horizontal_parent"] = function()
  -- Create A|B split
  child.lua('w.layout.split("right")')
  local result = child.lua([[
    local wins = vim.api.nvim_list_wins()
    local tree = vim.fn.winlayout()
    -- Check right window
    local parent = w.layout.util.get_dimensional_parent(tree, wins[2], true)
    return parent and parent[1] -- Should be "row"
  ]])
  assert_equal(result, "row")
end

T["get_dimensional_parent"]["finds_vertical_parent"] = function()
  -- Create A/B split
  child.lua('w.layout.split("down")')
  local result = child.lua([[
    local wins = vim.api.nvim_list_wins()
    local tree = vim.fn.winlayout()
    -- Check bottom window
    local parent = w.layout.util.get_dimensional_parent(tree, wins[2], false)
    return parent and parent[1] -- Should be "col"
  ]])
  assert_equal(result, "col")
end

T["get_dimensional_parent"]["handle_nested_splits"] = function()
  -- Create complex layout:
  -- +---+---+
  -- |   | B |
  -- | A +---+
  -- |   | C |
  -- +---+---+
  child.lua('w.layout.split("right")')
  child.lua('w.layout.split("down")')

  local result = child.lua([[
    local wins = vim.api.nvim_list_wins()
    local tree = vim.fn.winlayout()
    
    -- For window C:
    -- A: 1001, B: 1002, C: 1000
    local win_C = wins[3] -- Bottom window
    -- Get vertical parent
    local parent_v = w.layout.util.get_dimensional_parent(tree, win_C, false)
    -- Get horizontal parent
    local parent_h = w.layout.util.get_dimensional_parent(tree, win_C, true)
    
    return {
      vert_type = parent_v and parent_v[1],  -- Should be "col"
      horz_type = parent_h and parent_h[1]   -- Should be "row"
    }
  ]])
  assert_equal(result.vert_type, "col")
  assert_equal(result.horz_type, "row")
end

-- Test adjust_size
T["adjust_size"] = new_set()

T["adjust_size"]["handles_horizontal_split"] = function()
  -- Create A|B split
  child.lua('w.layout.split("right")')
  local before = child.lua([[
    local wins = vim.api.nvim_list_wins()
    return {
      left = vim.api.nvim_win_get_width(wins[1]),
      right = vim.api.nvim_win_get_width(wins[2])
    }
  ]])

  -- Adjust size with current window on the right
  child.lua([[
    local wins = vim.api.nvim_list_wins()
    local current_win = wins[2]  -- right window
    local tree = vim.fn.winlayout()
    local parent = w.layout.util.get_dimensional_parent(tree, current_win, true)
    w.layout.util.adjust_size(current_win, parent, true)
  ]])

  local after = child.lua([[
    local wins = vim.api.nvim_list_wins()
    return {
      left = vim.api.nvim_win_get_width(wins[1]),
      right = vim.api.nvim_win_get_width(wins[2])
    }
  ]])

  -- Check that right window got larger proportion
  local total = after.left + after.right
  local right_ratio = after.right / total
  H.assert_almost_equal(right_ratio, 0.618) -- Golden ratio
end

T["adjust_size"]["handles_vertical_split"] = function()
  -- Create A/B split
  child.lua('w.layout.split("down")')
  local before = child.lua([[
    local wins = vim.api.nvim_list_wins()
    return {
      top = vim.api.nvim_win_get_height(wins[1]),
      bottom = vim.api.nvim_win_get_height(wins[2])
    }
  ]])

  -- Adjust size with current window on the bottom
  child.lua([[
    local wins = vim.api.nvim_list_wins()
    local current_win = wins[2]  -- bottom window
    local tree = vim.fn.winlayout()
    local parent = w.layout.util.get_dimensional_parent(tree, current_win, false)
    w.layout.util.adjust_size(current_win, parent, false)
  ]])

  local after = child.lua([[
    local wins = vim.api.nvim_list_wins()
    return {
      top = vim.api.nvim_win_get_height(wins[1]),
      bottom = vim.api.nvim_win_get_height(wins[2])
    }
  ]])

  -- Check that bottom window got larger proportion
  local total = after.top + after.bottom
  local bottom_ratio = after.bottom / total
  H.assert_almost_equal(bottom_ratio, 0.618) -- Golden ratio
end

T["adjust_size"]["handles_nested_splits"] = function()
  -- Create complex layout:
  -- +---+---+
  -- |   | B |
  -- | A +---+
  -- |   | C |
  -- +---+---+
  child.lua('w.layout.split("right")')
  child.lua('w.layout.split("down")')

  -- Focus window C and adjust horizontal size
  child.lua([[
    local wins = vim.api.nvim_list_wins()
    local win_C = wins[1] -- Bottom window
    vim.api.nvim_set_current_win(win_C)
    
    local tree = vim.fn.winlayout()
    local parent_h = w.layout.util.get_dimensional_parent(tree, win_C, true)
    w.layout.util.adjust_size(win_C, parent_h, true)
  ]])

  local sizes = child.lua([[
    local wins = vim.api.nvim_list_wins()
    local win_A = wins[3] -- Left window
    local win_BC = vim.api.nvim_win_get_width(wins[2]) -- Width of B/C split
    
    return {
      left = vim.api.nvim_win_get_width(win_A),
      right = win_BC
    }
  ]])

  -- Check that right split (B/C) got larger proportion
  local total = sizes.left + sizes.right
  local right_ratio = sizes.right / total
  H.assert_almost_equal(right_ratio, 0.618) -- Golden ratio
end

T["adjust_size"]["handles_nil_parent"] = function()
  -- Test with single window (no parent)
  child.lua([[
    local current_win = vim.api.nvim_get_current_win()
    w.layout.util.adjust_size(current_win, nil, true)
  ]])
  -- Test should pass if no error is thrown
end

T["adjust_size"]["ignores_explorer_windows"] = function()
  -- Create split with explorer
  child.lua([[
    w.layout.split("right")  -- Create normal split to the right
    w.explorer.toggle_explorer()
  ]])

  local sizes = child.lua([[
    local explorer_width = w.config.options.explorer.window_width
    local wins = vim.api.nvim_list_wins()
    local normal_win
    for _, win in ipairs(wins) do
      if not w.layout.util.is_explorer(win) then
        normal_win = win
        break
      end
    end
    
    local tree = vim.fn.winlayout()
    local parent = w.layout.util.get_dimensional_parent(tree, normal_win, true)
    w.layout.util.adjust_size(normal_win, parent, true)
    
    return {
      explorer = vim.api.nvim_win_get_width(w.explorer.get_window()),
      normal = vim.api.nvim_win_get_width(normal_win)
    }
  ]])

  -- Explorer width should remain fixed
  assert_equal(sizes.explorer, child.lua_get("w.config.options.explorer.window_width"))
end

return T
