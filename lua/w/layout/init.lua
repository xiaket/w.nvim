local M = {}

-- Dependencies
local config = require("w.config")
local debug = require("w.debug")
local core = require("w.layout.core")
local util = require("w.layout.util")

M.update_previous_active_window = util.update_previous_active_window
M.get_previous_active_window = util.get_previous_active_window

---Split current window in specified direction or focus existing window
---@param direction "left"|"right"|"up"|"down"
---
---Usage scenarios:
---1. User wants to create a new split in specified direction
---   - Creates new window if no existing window in that direction
---   - Respects explorer window constraints (only allows right splits)
---   - Maintains golden ratio after split
---2. User wants to focus an existing window in that direction
---   - Switches focus to existing window if one exists
---   - Maintains window layout and split structure
---3. User triggers split in invalid direction for current layout
---   - Shows warning and prevents invalid split
---
---Expected behavior:
---1. For explorer windows:
---   - Only allows splits to the right
---   - Other directions are ignored with warning
---2. For normal windows:
---   - If adjacent window exists: focuses that window
---   - If no adjacent window: creates new split
---   - If split would violate layout rules: shows warning
---3. After any successful operation:
---   - Updates split tree structure
---   - Maintains golden ratio
---   - Records previous active window
---
---Split rules:
---1. Each split direction (horizontal or vertical) can contain at most two splits. Splits can be
---  nested. A horizontal split can only nest vertical splits inside it, and vice versa
---2. Explorer windows are special cases that don't follow the split tree rule
---3. When moving focus is desired, start searching from current split in the split tree, find the
---  nearest split in target direction. If not found, search in parent split, if no target found up
---  to root, do nothing (no-op). If multiple targets found, prefer the last active window
---
---Examples:
---1. User opens a file, then executes :WSplitLeft, this will create a horizontal split on the left
---  side, A|B. Focus switches to A. If user executes :WSplitLeft in A, it will be an no-op. If
---  user executes :WSplitRight in A, focus will be switched to B. No horizontal split will be created
---  when A and B are the only splits, except explorer window.
---2. In the following layout:
---  +---+---+
---  |   | B |
---  + A +---+
---  |   | C |
---  +---+---+
---    a. :WSplitLeft in either B or C will land in A.
---    b. No further vertical splits can be made among B/C, but we can do it in A.
---    c. We can create horizontal splits in B and C, but not A.
---    d. If we were in B then switched focus to A, running :WSplitRight in A will land in B as it
---      is the last active window.
---3. In the following layout:
---  +---+---+---+
---  |   |   B   |
---  + A +---+---+
---  |   | C | D |
---  +---+---+---+
---    a. When our focus is in C, :WSplitLeft will land in A, :WSplitRight will land in D, :WSplitUp
---      will land in B, and :WSplitDown will create new vertical splits.
---    b. If we were in C then switched focus to A, running :WSplitRight in A will land in C.
function M.split(direction)
  debug.log(string.rep("=", 40), "split called with direction:", direction, string.rep("=", 40))
  debug.dump_state("layout:enter split")
  local current = vim.api.nvim_get_current_win()

  -- Only allow right split for explorer windows
  if util.is_explorer(current) then
    if direction ~= "right" then
      debug.log("explorer window only allows right split")
      return
    end
  end

  -- Try to find existing window to focus
  local target_win = core.find_target_window(current, direction)
  debug.log("target window:", target_win)
  if target_win then
    vim.api.nvim_set_current_win(target_win)
    return
  end

  -- Check if new split is allowed
  if not core.can_split(current, direction) then
    debug.log("Cannot create new split in this direction")
    return
  end

  core.create_split(direction)
end

---Redraw all windows according to golden ratio
---
---The resize rules:
---1. Golden Ratio Rule:
---   - In any split, the active window takes up 0.618 of the space
---   - The inactive window naturally takes up the remaining 0.382 of the space
---   - Due to the split tree nesting rule in M.split, this ratio applies at any level of splits
---
---2. Explorer Window Rule:
---   - Explorer window has a fixed width, not following the golden ratio
---   - Creating explorer window will reduce maximum window width, triggers a redraw.
---
---3. Active Window Rule:
---   - When a window gains focus, it should get 0.618 of the space in its containing split
-- in layout/init.lua
function M.redraw()
  local current_win = vim.api.nvim_get_current_win()
  if util.is_explorer(current_win) then
    return
  end

  local layout = vim.fn.winlayout()

  -- Handle resize based on window changes
  local prev_win = util.get_previous_active_window()
  if not prev_win then
    -- No previous window means this is a new split
    -- Find immediate parent to determine split direction
    local _, parent = util.find_window_in_tree(layout, current_win, nil)
    if parent then
      -- Only adjust the dimension that matches the split direction
      util.adjust_size(parent, parent[1] == "row")
    end
    return
  end

  -- Adjust only relevant dimension based on movement direction
  local direction = util.get_relative_direction(prev_win, current_win)
  if direction == "left" or direction == "right" then
    -- Horizontal movement - adjust width
    local row_parent = util.get_dimensional_parent(layout, current_win, true)
    util.adjust_size(current_win, row_parent, true)
  elseif direction == "up" or direction == "down" then
    -- Vertical movement - adjust height
    local col_parent = util.get_dimensional_parent(layout, current_win, false)
    util.adjust_size(current_win, col_parent, false)
  end
end

-- Highlight window with adjusted brightness
local function highlight_window(winid, is_active)
  local offset = config.options.window_highlight_offset
  if not offset then
    return
  end
  local hl_name = is_active and "WinActive" or "WinInactive"
  local brightness = is_active and offset or -offset
  local base_bg = util.get_background_color()
  vim.api.nvim_set_hl(0, hl_name, { bg = util.adjust_brightness(base_bg, brightness) })
  vim.api.nvim_win_set_option(winid, "winhl", "Normal:" .. hl_name)
end

function M.highlight_active_window(winid)
  highlight_window(winid, true)
end

function M.highlight_inactive_window(winid)
  highlight_window(winid, false)
end

return M
