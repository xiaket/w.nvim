-- tests/test_layout.lua
local new_set = MiniTest.new_set

-- Creating test sets
local T = new_set()

-- setup test environment.
T.setup = function()
  -- load modules
  _G.w = {}
  _G.w.init = require("w.init")
  _G.w.config = require("w.config")
  _G.w.layout = require("w.layout")
end

-- setup for each test.
local function reset_windows()
  -- Close all windows except for the current one.
  local current = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= current then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  _G.w.init.setup()

  -- Ensure there's only one buffer.
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(current, buf)

  -- reset state in w.layout
  package.loaded["w.layout"] = nil
  _G.w.layout = require("w.layout")

  return current
end

T.hooks = {
  pre = function()
    reset_windows()
  end,
}

local function assert_count_and_cursor_position(count, position)
  MiniTest.expect.equality(#vim.api.nvim_list_wins(), count)
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), position)
end

local expect_size_match = MiniTest.new_expectation(
  "window size match",
  function(size1, size2)
    return size1 - size2 <= 1 or size2 - size1 <= 1
  end,
  -- Fail context
  function(size1, size2)
    return string.format(
      "Size: Expected window size should be around %d\nObserved string: %d",
      size1,
      size2
    )
  end
)

-- Testing split logic.
T["split"] = new_set()

T["split"]["native_split_still_works"] = function()
  reset_windows()
  local wins_before = #vim.api.nvim_list_wins()
  vim.cmd("split") -- Native split should still work.
  MiniTest.expect.equality(#vim.api.nvim_list_wins(), wins_before + 1)
  vim.cmd("vsplit") -- Native split bypass our split logic.
  MiniTest.expect.equality(#vim.api.nvim_list_wins(), wins_before + 2)
end

-- Test the case where we have horizontal splits, A|B.
-- In this case, running WSplitRight on B and WSplitLeft on A should be no-op.
T["split"]["should_prevent_invalid_horizontal_splits"] = function()
  reset_windows()

  -- Create a split on the right.
  w.layout.split("right")
  local wins_before = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins_before, 2)
  local left_win, right_win = unpack(vim.api.nvim_list_wins())

  -- Split right on right split should be no-op.
  vim.api.nvim_set_current_win(right_win)
  w.layout.split("right")
  MiniTest.expect.equality(#vim.api.nvim_list_wins(), #wins_before)

  -- Split left on left split should be no-op.
  vim.api.nvim_set_current_win(left_win)
  w.layout.split("left")
  MiniTest.expect.equality(#vim.api.nvim_list_wins(), #wins_before)
end

-- Test the case where we have vertical splits, A/B.
-- In this case, running WSplitDown on B and WSplitUp on A should be no-op.
T["split"]["should_prevent_invalid_vertical_splits"] = function()
  reset_windows()

  -- Create a split on the right.
  w.layout.split("down")
  local wins_before = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins_before, 2)
  local up_win, down_win = unpack(vim.api.nvim_list_wins())

  -- Split down on down split should be no-op.
  vim.api.nvim_set_current_win(down_win)
  w.layout.split("down")
  MiniTest.expect.equality(#vim.api.nvim_list_wins(), #wins_before)

  -- Split left on left split should be no-op.
  vim.api.nvim_set_current_win(up_win)
  w.layout.split("up")
  MiniTest.expect.equality(#vim.api.nvim_list_wins(), #wins_before)
end

-- Test the case where we have horizontal splits, A|B. Then we split B into B/C
-- So in this case we have A on the left, B on top right, and C on bottom right.
-- Running WSplitLeft on B or C should land in A.
--   +---+---+
--   |   | B |
--   + A +---+
--   |   | C |
--   +---+---+
T["split"]["should_handle_three_splits_operations"] = function()
  reset_windows()

  -- Create A and B.
  w.layout.split("right")
  local wins = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins, 2)

  -- We are in B right now, split down
  w.layout.split("down")

  -- We should have three windows now.
  local wins_after_vsplit = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins_after_vsplit, #wins + 1)

  local tree = vim.fn.winlayout()
  -- { "row", { { "leaf", 1001 }, { "col", { { "leaf", 1002 }, { "leaf", 1000 } } } } }
  local win_A = tree[2][1][2]
  local win_B = tree[2][2][2][1][2]
  local win_C = tree[2][2][2][2][2]

  -- Run split left on B should land on A.
  vim.api.nvim_set_current_win(win_B)
  w.layout.split("left")
  assert_count_and_cursor_position(#wins + 1, win_A)

  -- We are in A right now, to back to C
  vim.api.nvim_set_current_win(win_C)
  -- Run split left on C should land on A.
  w.layout.split("left")
  assert_count_and_cursor_position(#wins + 1, win_A)

  -- Run split right on A should land on C as it is the last active window.
  w.layout.split("right")
  assert_count_and_cursor_position(#wins + 1, win_C)

  -- Run split up on C should land on B.
  w.layout.split("up")
  assert_count_and_cursor_position(#wins + 1, win_B)
end

-- Test the case where we have horizontal splits, A|B. Then we split B into B/C
-- After that we split C horizontally into C|D.
-- +---+---+---+
-- |   |   B   |
-- + A +---+---+
-- |   | C | D |
-- +---+---+---+
-- Running WSplitLeft on D should land in C.
-- Running WSplitLeft on C should land in A.
T["split"]["should_handle_complex_split_operations"] = function()
  reset_windows()

  w.layout.split("right")
  local wins_after_right = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins_after_right, 2)

  w.layout.split("down")
  local wins_after_vsplit = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins_after_vsplit, 3)

  -- Do split Down in C before creating D, should be no-op.
  local wins_before_down = #vim.api.nvim_list_wins()
  w.layout.split("down")
  MiniTest.expect.equality(#vim.api.nvim_list_wins(), wins_before_down)

  -- Creating D.
  w.layout.split("right")
  local wins = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins, wins_before_down + 1)

  local tree = vim.fn.winlayout()
  -- { "row", { { "leaf", 1001 }, { "col", { { "leaf", 1002 }, { "row", { { "leaf", 1003 }, { "leaf", 1000 } } } } } } }
  local win_A = tree[2][1][2]
  local win_B = tree[2][2][2][1][2]
  local win_C = tree[2][2][2][2][2][1][2]
  local win_D = tree[2][2][2][2][2][2][2]
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), win_D)

  -- Split left in D should land in C
  w.layout.split("left")
  assert_count_and_cursor_position(#wins, win_C)

  -- Split left in C should land in A
  w.layout.split("left")
  assert_count_and_cursor_position(#wins, win_A)

  -- Split right in A should land in C, as it is the last active split.
  w.layout.split("right")
  assert_count_and_cursor_position(#wins, win_C)

  w.layout.split("up")
  assert_count_and_cursor_position(#wins, win_B)
end

T["navigation"] = new_set()

T["navigation"]["should_find_adjacent_window"] = function()
  reset_windows()

  -- 使用原生命令创建分割
  vim.cmd("vsplit")

  -- 确保我们有两个窗口
  local wins = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins, 2)

  -- 验证布局
  local has_right = vim.api.nvim_win_get_position(wins[2])[2] > 0
  MiniTest.expect.equality(has_right, true)
end

T["calculate_window_sizes"] = new_set()

-- Basic two window horizontal split
-- +---+---+
-- | A | B |
-- +---+---+
T["calculate_window_sizes"]["handles_basic_horizontal_split"] = function()
  reset_windows()

  w.layout.split("right") -- Create basic A|B layout
  local wins = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins, 2)

  local win_A, win_B = unpack(wins)
  local total_width = vim.o.columns

  local sizes = w.layout.calculate_window_sizes()

  -- Active window (B) should get golden ratio
  expect_size_match(sizes[win_B].width, math.floor(total_width * w.config.options.split_ratio))
  -- Remaining window (A) should get rest
  expect_size_match(sizes[win_A].width, total_width - sizes[win_B].width)
  -- Heights should be the same
  expect_size_match(sizes[win_A].height, sizes[win_B].height)
end

-- Three window nested split
-- +---+---+
-- |   | B |
-- | A +---+
-- |   | C |
-- +---+---+
T["calculate_window_sizes"]["handles_nested_splits"] = function()
  reset_windows()

  -- Create layout
  w.layout.split("right")
  local wins_first = vim.api.nvim_list_wins()
  local win_A, win_B = unpack(wins_first)
  vim.api.nvim_set_current_win(win_B)
  w.layout.split("down")

  local wins = vim.api.nvim_list_wins()
  MiniTest.expect.equality(#wins, 3)

  -- Find window C
  local win_C
  for _, win in ipairs(wins) do
    if win ~= win_A and win ~= win_B then
      win_C = win
      break
    end
  end

  local total_width = vim.o.columns
  local total_height = vim.o.lines

  -- Test with C as active window
  vim.api.nvim_set_current_win(win_C)
  local sizes = w.layout.calculate_window_sizes()

  -- A should take up left side
  expect_size_match(
    sizes[win_A].width,
    math.floor(total_width * (1 - w.config.options.split_ratio))
  )
  expect_size_match(sizes[win_A].height, total_height)

  -- B and C should split right side
  MiniTest.expect.equality(
    sizes[win_B].width,
    math.floor(total_width * w.config.options.split_ratio)
  )
  MiniTest.expect.equality(sizes[win_C].width, sizes[win_B].width)

  -- C (active) should get golden ratio of height
  local right_height = total_height
  MiniTest.expect.equality(
    sizes[win_C].height,
    math.floor(right_height * w.config.options.split_ratio)
  )
  MiniTest.expect.equality(sizes[win_B].height, right_height - sizes[win_C].height)
end

-- Four window complex layout
-- +---+---+---+
-- |   |   B   |
-- | A +---+---+
-- |   | C | D |
-- +---+---+---+
T["calculate_window_sizes"]["handles_complex_layout"] = function()
  reset_windows()

  -- Create layout
  w.layout.split("right")
  local wins_first = vim.api.nvim_list_wins()
  local win_A, win_B = unpack(wins_first)
  vim.api.nvim_set_current_win(win_B)
  w.layout.split("down")
  local win_C = vim.api.nvim_get_current_win()
  w.layout.split("right")
  local win_D = vim.api.nvim_get_current_win()

  local total_width = vim.o.columns
  local total_height = vim.o.lines

  -- Test with C as active window
  vim.api.nvim_set_current_win(win_C)
  local sizes = w.layout.calculate_window_sizes()

  -- A should get non-golden ratio of width
  expect_size_match(
    sizes[win_A].width,
    math.floor(total_width * (1 - w.config.options.split_ratio))
  )
  expect_size_match(sizes[win_A].height, total_height)

  -- Right section total width
  local right_width = math.floor(total_width * w.config.options.split_ratio)

  -- B width should be full right section
  expect_size_match(sizes[win_B].width, right_width)

  -- C (active) and D should split remaining right section width
  expect_size_match(sizes[win_C].width, math.floor(right_width * w.config.options.split_ratio))
  expect_size_match(sizes[win_D].width, right_width - sizes[win_C].width)
end

-- Test with explorer window
T["calculate_window_sizes"]["handles explorer window"] = function()
  reset_windows()
  local current = vim.api.nvim_get_current_win()

  -- Set up explorer window
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_option(buf, "filetype", w.config.options.explorer_window_filetype)
  vim.api.nvim_win_set_buf(current, buf)

  -- Create another window
  w.layout.split("right")

  local sizes = w.layout.calculate_window_sizes()

  -- Explorer should have fixed width
  expect_size_match(sizes[current].width, w.config.options.explorer_window_width)
end

return T
