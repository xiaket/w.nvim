local M = {}
local config = require("w.config")
local state = require("w.explorer.state")

local function map(buf, keys, callback)
  if type(keys) == "string" then
    keys = { keys }
  end
  for _, key in ipairs(keys) do
    vim.api.nvim_buf_set_keymap(buf, "n", key, "", {
      callback = callback,
      noremap = true,
      silent = true,
    })
  end
end

function M.setup_buffer_autocmds(buf)
  local group = vim.api.nvim_create_augroup(config.const.explorer_augroup, { clear = true })
  local ui = require("w.explorer.ui")

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      local win = state.get_window()
      if win then
        state.set_last_position(vim.api.nvim_win_get_cursor(win)[1])
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = group,
    callback = ui.highlight_current_file,
  })
end

function M.setup_buffer_keymaps(buf)
  local actions = require("w.explorer.actions")

  map(buf, config.options.explorer.keymaps.close, require("w.explorer").toggle_explorer)
  map(buf, config.options.explorer.keymaps.go_up, actions.go_up)
  map(buf, config.options.explorer.keymaps.open, actions.open_current)
end

function M.setup_truncation_keymap(buf, is_truncated)
  vim.api.nvim_buf_set_keymap(buf, "n", "j", "", {
    callback = function()
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      local line_count = vim.api.nvim_buf_line_count(buf)

      if is_truncated and cursor_line == line_count then
        vim.schedule(function()
          local fs = require("w.explorer.fs")
          local ui = require("w.explorer.ui")
          local current_dir = state.get_current_dir()
          local full_files = fs.read_dir(current_dir, true)
          ui.display_files(full_files, false)
        end)
        return ""
      end

      return "j"
    end,
    expr = true,
    noremap = true,
    silent = true,
  })
end

return M
