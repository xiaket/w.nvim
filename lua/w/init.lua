local M = {}

-- Create user commands
local function create_commands()
  local commands = {
    WToggleExplorer = { module = "explorer", fn = "toggle_explorer" },
    WSplitLeft = { module = "layout", fn = "split", args = { "left" } },
    WSplitRight = { module = "layout", fn = "split", args = { "right" } },
    WSplitUp = { module = "layout", fn = "split", args = { "up" } },
    WSplitDown = { module = "layout", fn = "split", args = { "down" } },
    WPrevBuffer = {
      module = "explorer",
      fn = "with_editor_window",
      args = {
        function()
          vim.cmd("bprevious")
        end,
      },
    },
    WNextBuffer = {
      module = "explorer",
      fn = "with_editor_window",
      args = {
        function()
          vim.cmd("bnext")
        end,
      },
    },
  }

  for cmd_name, cmd_def in pairs(commands) do
    vim.api.nvim_create_user_command(cmd_name, function()
      local mod = require("w." .. cmd_def.module)
      if cmd_def.args then
        mod[cmd_def.fn](unpack(cmd_def.args))
      else
        mod[cmd_def.fn]()
      end
      require("w.layout").redraw()
    end, {})
  end
end

-- Create autocommands
local function create_autocommands()
  local config = require("w.config")

  local dir_filetype = config.const.dir_filetype
  local group = vim.api.nvim_create_augroup(config.const.augroup, { clear = true })

  -- Handle window resize
  vim.api.nvim_create_autocmd({ "VimResized" }, {
    group = group,
    callback = function()
      require("w.layout").redraw()
    end,
  })

  -- update prev_active_window.
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      require("w.layout").update_previous_active_window()
      if config.options.window_highlight_offset ~= nil then
        local win = vim.api.nvim_get_current_win()
        require("w.layout").highlight_inactive_window(win)
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = config.const.augroup,
    callback = function()
      if config.options.window_highlight_offset ~= nil then
        local win = vim.api.nvim_get_current_win()
        require("w.layout").highlight_active_window(win)
      end
    end,
  })

  -- Handle directory buffers directly
  -- Instead of doing explorer.open right here, we simply set the filetype of the buffer,
  -- this is to avoid the complication in buffer initialization.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      local bufname = vim.api.nvim_buf_get_name(0)
      if vim.fn.isdirectory(bufname) == 1 then
        vim.bo.filetype = dir_filetype
      end
    end,
  })

  -- Handle directories through filetype
  vim.api.nvim_create_autocmd("FileType", {
    pattern = dir_filetype,
    group = group,
    callback = function()
      local bufname = vim.api.nvim_buf_get_name(0)
      vim.schedule(function()
        require("w.explorer").open(bufname)
      end)
    end,
  })
end

-- Setup function called by lazy.nvim
function M.setup(opts)
  -- Load and validate config
  if not require("w.config").setup(opts) then
    -- Error handling is done in config.setup, nothing more to be done here.
    return
  end

  -- Create commands and autocommands
  create_commands()
  create_autocommands()
end

return M
