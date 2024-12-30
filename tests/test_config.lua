-- tests/test_config.lua
local H = require("tests.helpers")
local new_set = H.new_set
local assert_equal = H.assert_equal

-- Create child process with required modules
local child, hooks = H.new_child({ "config" })

-- Create test set with hooks
local T = new_set({ hooks = hooks })

-- Test setup functionality
T["setup"] = new_set()

T["setup"]["should_merge_with_defaults"] = function()
  -- Test partial override
  local success = child.lua([[
    return w.config.setup({
      explorer_window_width = 30,
      max_files = 200,
    })
  ]])
  assert_equal(success, true)

  local options = child.lua_get("w.config.options")
  assert_equal(options.explorer_window_width, 30)
  assert_equal(options.max_files, 200)
end

T["setup"]["should_merge_nested_tables"] = function()
  local success = child.lua([[
    return w.config.setup({
      explorer_window_keymaps = {
        close = "<C-c>",
        -- go_up and open should remain default
      },
    })
  ]])
  assert_equal(success, true)

  local options = child.lua_get("w.config.options")
  assert_equal(options.explorer_window_keymaps.close, "<C-c>")
  assert_equal(options.explorer_window_keymaps.go_up, "h")
  assert_equal(options.explorer_window_keymaps.open, "<CR>")
end

-- Test validation
T["validation"] = new_set()

T["validation"]["should_validate_explorer_window_width"] = function()
  -- Test invalid values
  local success = child.lua([[
    return w.config.setup({ explorer_window_width = 5 })
  ]])
  assert_equal(success, false)

  success = child.lua([[
    return w.config.setup({ explorer_window_width = "25" })
  ]])
  assert_equal(success, false)

  -- Test valid value
  success = child.lua([[
    return w.config.setup({ explorer_window_width = 30 })
  ]])
  assert_equal(success, true)

  local options = child.lua_get("w.config.options")
  assert_equal(options.explorer_window_width, 30)
end

T["validation"]["should_validate_max_files"] = function()
  -- Test invalid values
  local success = child.lua([[
    return w.config.setup({ max_files = 0 })
  ]])
  assert_equal(success, false)

  success = child.lua([[
    return w.config.setup({ max_files = -1 })
  ]])
  assert_equal(success, false)

  success = child.lua([[
    return w.config.setup({ max_files = "100" })
  ]])
  assert_equal(success, false)

  -- Test valid value
  success = child.lua([[
    return w.config.setup({ max_files = 50 })
  ]])
  assert_equal(success, true)

  local options = child.lua_get("w.config.options")
  assert_equal(options.max_files, 50)
end

T["validation"]["should_validate_split_ratio"] = function()
  -- Test invalid values
  local success = child.lua([[
    return w.config.setup({ split_ratio = 0 })
  ]])
  assert_equal(success, false)

  success = child.lua([[
    return w.config.setup({ split_ratio = 1 })
  ]])
  assert_equal(success, false)

  success = child.lua([[
    return w.config.setup({ split_ratio = "0.5" })
  ]])
  assert_equal(success, false)

  -- Test valid value
  success = child.lua([[
    return w.config.setup({ split_ratio = 0.5 })
  ]])
  assert_equal(success, true)

  local options = child.lua_get("w.config.options")
  assert_equal(options.split_ratio, 0.5)
end

T["validation"]["should_validate_show_hidden"] = function()
  -- Test invalid value
  local success = child.lua([[
    return w.config.setup({ show_hidden = "true" })
  ]])
  assert_equal(success, false)

  -- Test valid values
  success = child.lua([[
    return w.config.setup({ show_hidden = true })
  ]])
  assert_equal(success, true)

  local options = child.lua_get("w.config.options")
  assert_equal(options.show_hidden, true)

  success = child.lua([[
    return w.config.setup({ show_hidden = false })
  ]])
  assert_equal(success, true)

  options = child.lua_get("w.config.options")
  assert_equal(options.show_hidden, false)
end

return T
