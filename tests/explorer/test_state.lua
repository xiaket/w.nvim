local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal

local child, hooks = H.new_child({ "init", "config", "layout", "explorer", "explorer.state" })
local T = new_set({ hooks = hooks })

-- Helper function to create an invalid window handle
local function get_invalid_win()
  -- Create and immediately close a window to get invalid handle
  child.cmd("split")
  local win = child.api.nvim_get_current_win()
  child.cmd("close")
  return win
end

-- Helper function to create an invalid buffer handle
local function get_invalid_buf()
  local buf = child.api.nvim_create_buf(false, true)
  child.api.nvim_buf_delete(buf, { force = true })
  return buf
end

-- Test window getter/setter
T["window"] = new_set()

T["window"]["should_handle_valid_window"] = function()
  child.cmd("split")
  local win = child.api.nvim_get_current_win()

  -- Set and verify
  child.lua("w.explorer.state.set_window(...)", { win })
  assert_equal(child.lua_get("w.explorer.state.get_window()"), win)
end

T["window"]["should_handle_nil_window"] = function()
  child.lua("w.explorer.state.set_window(nil)")
  assert_equal(child.lua_get("w.explorer.state.get_window()"), vim.NIL)
end

T["window"]["should_handle_invalid_window"] = function()
  local invalid_win = get_invalid_win()

  -- Set invalid window
  child.lua("w.explorer.state.set_window(...)", { invalid_win })
  -- Should return nil for invalid window
  assert_equal(child.lua_get("w.explorer.state.get_window()"), vim.NIL)
end

-- Test buffer getter/setter
T["buffer"] = new_set()

T["buffer"]["should_handle_valid_buffer"] = function()
  local buf = child.api.nvim_create_buf(false, true)

  child.lua("w.explorer.state.set_buffer(...)", { buf })
  assert_equal(child.lua_get("w.explorer.state.get_buffer()"), buf)
end

T["buffer"]["should_handle_nil_buffer"] = function()
  child.lua("w.explorer.state.set_buffer(nil)")
  assert_equal(child.lua_get("w.explorer.state.get_buffer()"), vim.NIL)
end

T["buffer"]["should_handle_invalid_buffer"] = function()
  local invalid_buf = get_invalid_buf()

  child.lua("w.explorer.state.set_buffer(...)", { invalid_buf })
  assert_equal(child.lua_get("w.explorer.state.get_buffer()"), vim.NIL)
end

-- Test current directory getter/setter
T["current_dir"] = new_set()

T["current_dir"]["should_normalize_paths"] = function()
  local test_paths = {
    { input = "/test/path/", expected = "/test/path" },
    { input = "/test/path", expected = "/test/path" },
    {
      input = "relative/path/",
      expected = child.fn.fnamemodify("relative/path", ":p"):gsub("/$", ""),
    },
  }

  for _, test in ipairs(test_paths) do
    child.lua("w.explorer.state.set_current_dir(...)", { test.input })
    assert_equal(child.lua_get("w.explorer.state.get_current_dir()"), test.expected)
  end
end

-- Test last position getter/setter
T["last_position"] = new_set()

T["last_position"]["should_handle_valid_positions"] = function()
  child.lua("w.explorer.state.set_last_position(5)")
  assert_equal(child.lua_get("w.explorer.state.get_last_position()"), 5)
end

T["last_position"]["should_handle_nil_position"] = function()
  child.lua("w.explorer.state.set_last_position(nil)")
  assert_equal(child.lua_get("w.explorer.state.get_last_position()"), vim.NIL)
end

T["last_position"]["should_ignore_invalid_positions"] = function()
  -- Set valid position first
  child.lua("w.explorer.state.set_last_position(5)")

  -- Try setting invalid positions
  local invalid_positions = { 0, -1, "string", {} }
  for _, pos in ipairs(invalid_positions) do
    child.lua("w.explorer.state.set_last_position(...)", { pos })
    -- Should still have old valid position
    assert_equal(child.lua_get("w.explorer.state.get_last_position()"), 5)
  end
end

-- Test state consistency
T["state_consistency"] = new_set()

T["state_consistency"]["should_maintain_state_across_operations"] = function()
  -- Set up initial state
  child.cmd("split")
  local win = child.api.nvim_get_current_win()
  local buf = child.api.nvim_create_buf(false, true)
  local dir = "/test/path"
  local pos = 3

  -- Set all state
  child.lua(
    [[
    local win, buf, dir = ...
    local state = require('w.explorer.state')
    state.set_window(win)
    state.set_buffer(buf)
    state.set_current_dir(dir)
  ]],
    { win, buf, dir, pos }
  )

  -- Verify all state is maintained
  assert_equal(child.lua_get("w.explorer.state.get_window()"), win)
  assert_equal(child.lua_get("w.explorer.state.get_buffer()"), buf)
  assert_equal(child.lua_get("w.explorer.state.get_current_dir()"), dir)
end

return T
