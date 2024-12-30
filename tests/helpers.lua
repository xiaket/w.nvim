-- tests/helpers.lua
local H = {}

-- Common dependencies
H.new_set = MiniTest.new_set
H.assert_equal = MiniTest.expect.equality
H.assert_almost_equal = function(a, b)
  local diff = math.abs(a - b)
  MiniTest.expect.equality(diff <= 1, true)
end

-- Create pre-configured child process helper
H.new_child = function(modules)
  modules = modules or {}
  local child = MiniTest.new_child_neovim()

  -- Pre-configure hooks
  local hooks = {
    pre_case = function()
      if not child.is_running() then
        child.start({ "-u", "tests/init_tests.lua" })
      else
        child.restart({ "-u", "tests/init_tests.lua" })
      end

      -- Setup base environment
      child.lua([[w = {}]])

      child.lua([[w.init = require('w.init')]])
      child.lua([[w.init.setup()]])

      -- Load requested modules
      for _, mod in ipairs(modules) do
        child.lua(string.format([[w.%s = require('w.%s')]], mod, mod))
      end
    end,
    post_once = child.stop,
  }

  return child, hooks
end

-- Common window helper functions
H.window = {
  get_count = function(child)
    return child.lua_get("#vim.api.nvim_list_wins()")
  end,

  assert_count = function(child, count)
    H.assert_equal(child.lua_get("#vim.api.nvim_list_wins()"), count)
  end,

  expect_count_and_pos = function(child, count, win_id)
    H.assert_equal(H.window.get_count(child), count)
    H.assert_equal(child.lua_get("vim.api.nvim_get_current_win()"), win_id)
  end,
}

return H
