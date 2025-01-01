local M = {}

-- Dependencies
local config = require("w.config")

-- Create user commands
local function create_commands()
  local function cmd(name, fn)
    vim.api.nvim_create_user_command(name, fn, {})
  end

  cmd("WToggleExplorer", function()
    require("w.explorer").toggle_explorer()
  end)

  cmd("WSplitLeft", function()
    require("w.layout").split("left")
  end)

  cmd("WSplitRight", function()
    require("w.layout").split("right")
  end)

  cmd("WSplitUp", function()
    require("w.layout").split("up")
  end)

  cmd("WSplitDown", function()
    require("w.layout").split("down")
  end)
end

-- Create autocommands
local function create_autocommands()
  local dir_filetype = "w.dir"
  local group = vim.api.nvim_create_augroup("W", { clear = true })

  -- Handle window resize
  vim.api.nvim_create_autocmd({ "WinEnter", "VimResized" }, {
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
    end,
  })

  -- Handle directory buffers directly
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
  if not config.setup(opts) then
    -- Error handling is done in config.setup, nothing more to be done here.
    return
  end

  -- Create commands and autocommands
  create_commands()
  create_autocommands()
end

return M
